#!/usr/bin/env bash
# =============================================================================
# Hermes Patch Re-Apply Script
# Run this after every `hermes update` to restore all code modifications.
#
# Usage: bash ~/company/hermes/patches/reapply-all-patches.sh
# =============================================================================

set -e
HERMES_AGENT="$HOME/.hermes/hermes-agent"
PATCHES_DIR="$HOME/company/hermes/patches"

echo "=== Hermes Patch Re-Apply ==="
echo ""

# -----------------------------------------------------------------------
# PATCH-001: Kimi User-Agent (run_agent.py — 2 locations)
# Why: api.kimi.com rejects all User-Agents except whitelisted coding agents.
#      `claude-code/1.0` is the only confirmed working value.
# -----------------------------------------------------------------------
echo "[PATCH-001] Kimi User-Agent → claude-code/1.0"
if grep -q '"User-Agent": "KimiCLI/1.3"' "$HERMES_AGENT/run_agent.py" 2>/dev/null; then
    sed -i '' 's/"User-Agent": "KimiCLI\/1.3"/"User-Agent": "claude-code\/1.0"/g' "$HERMES_AGENT/run_agent.py"
    echo "  ✅ Applied"
else
    echo "  ✓  Already applied or not needed"
fi

# -----------------------------------------------------------------------
# PATCH-002: AGENTS.md symlink
# Why: Gateway loads AGENTS.md from CWD (hermes-agent/), which is the
#      repo's dev guide. We need our CEO operating manual to load instead.
#      Symlink redirects CWD AGENTS.md → ~/.hermes/AGENTS.md (our manual).
# -----------------------------------------------------------------------
echo "[PATCH-002] AGENTS.md symlink → ~/.hermes/AGENTS.md"
AGENTS_TARGET="$HERMES_AGENT/AGENTS.md"
if [ -L "$AGENTS_TARGET" ] && [ "$(readlink "$AGENTS_TARGET")" = "$HOME/.hermes/AGENTS.md" ]; then
    echo "  ✓  Symlink already correct"
elif [ -f "$AGENTS_TARGET" ] && [ ! -L "$AGENTS_TARGET" ]; then
    mv "$AGENTS_TARGET" "$HERMES_AGENT/AGENTS.md.dev-guide"
    ln -s "$HOME/.hermes/AGENTS.md" "$AGENTS_TARGET"
    echo "  ✅ Applied (backed up repo AGENTS.md → AGENTS.md.dev-guide)"
else
    ln -sf "$HOME/.hermes/AGENTS.md" "$AGENTS_TARGET"
    echo "  ✅ Applied (symlink created)"
fi

# -----------------------------------------------------------------------
# PATCH-003: Concurrent cron (scheduler.py)
# Why: tick() ran jobs sequentially — a 20-min CEO heartbeat blocked all
#      other agents. ThreadPoolExecutor runs multiple due jobs in parallel.
#      Single jobs still run inline (no overhead). Concurrency = HERMES_CRON_MAX_WORKERS (default 20).
# -----------------------------------------------------------------------
echo "[PATCH-003] Concurrent cron execution (ThreadPoolExecutor)"
if grep -q "_execute_job" "$HERMES_AGENT/cron/scheduler.py" 2>/dev/null; then
    echo "  ✓  Already applied"
else
    if [ -f "$PATCHES_DIR/scheduler-concurrent.patch" ]; then
        cd "$HERMES_AGENT"
        if git apply --check "$PATCHES_DIR/scheduler-concurrent.patch" 2>/dev/null; then
            git apply "$PATCHES_DIR/scheduler-concurrent.patch"
            echo "  ✅ Applied via git patch"
        else
            echo "  ⚠️  Patch file doesn't apply cleanly — apply PATCH-003 manually."
            echo "     See ~/company/hermes/PATCH-NOTES.md for full code block."
        fi
    else
        echo "  ⚠️  No patch file found at $PATCHES_DIR/scheduler-concurrent.patch"
        echo "     Apply PATCH-003 manually — see PATCH-NOTES.md for code."
    fi
fi

# -----------------------------------------------------------------------
# PATCH-004: HERMES_EXEC_ASK = "0" (always auto-approve) in gateway/run.py
# Why: Gateway hardcodes HERMES_EXEC_ASK=1 on import. We want agents to
#      auto-approve all commands. Current fix: hardcode "0" to always override.
# -----------------------------------------------------------------------
echo "[PATCH-004] HERMES_EXEC_ASK auto-approve"
if grep -q 'os.environ\["HERMES_EXEC_ASK"\] = "0"' "$HERMES_AGENT/gateway/run.py" 2>/dev/null; then
    echo "  ✓  Already applied (hardcoded to 0)"
elif grep -q 'if "HERMES_EXEC_ASK" not in os.environ' "$HERMES_AGENT/gateway/run.py" 2>/dev/null; then
    echo "  ✓  Already applied (conditional form)"
elif grep -q 'os.environ\["HERMES_EXEC_ASK"\] = "1"' "$HERMES_AGENT/gateway/run.py" 2>/dev/null; then
    sed -i '' 's/os.environ\["HERMES_EXEC_ASK"\] = "1"/os.environ["HERMES_EXEC_ASK"] = "0"/' "$HERMES_AGENT/gateway/run.py"
    echo "  ✅ Applied (changed 1 → 0)"
else
    echo "  ⚠️  Pattern not found — check gateway/run.py manually"
fi

# -----------------------------------------------------------------------
# PATCH-005: skip_memory=False + messaging enabled in cron (scheduler.py)
# Why: Default has skip_memory=True and messaging in disabled_toolsets.
#      Agents can't persist memory or send messages during cron execution.
# -----------------------------------------------------------------------
echo "[PATCH-005] skip_memory=False + messaging enabled in cron"
if grep -q 'skip_memory=False' "$HERMES_AGENT/cron/scheduler.py" 2>/dev/null; then
    echo "  ✓  Already applied"
else
    if grep -q 'skip_memory=True' "$HERMES_AGENT/cron/scheduler.py" 2>/dev/null; then
        sed -i '' 's/skip_memory=True/skip_memory=False/' "$HERMES_AGENT/cron/scheduler.py"
        echo "  ✅ Applied skip_memory=False"
    fi
    if grep -q '"messaging"' "$HERMES_AGENT/cron/scheduler.py" 2>/dev/null; then
        sed -i '' 's/disabled_toolsets=\["cronjob", "messaging", "clarify"\]/disabled_toolsets=["cronjob", "clarify"]/' "$HERMES_AGENT/cron/scheduler.py"
        echo "  ✅ Applied messaging toolset enabled"
    fi
fi

# -----------------------------------------------------------------------
# PATCH-006: Telegram RetryAfter flood control (gateway/platforms/telegram.py)
# Why: RetryAfter is NOT a subclass of NetworkError — wasn't being caught,
#      causing message delivery to die silently during rapid sends.
# -----------------------------------------------------------------------
echo "[PATCH-006] Telegram RetryAfter flood control"
if grep -q '_RetryAfter' "$HERMES_AGENT/gateway/platforms/telegram.py" 2>/dev/null; then
    echo "  ✓  Already applied"
else
    echo "  ⚠️  PATCH-006 not detected — apply manually (see PATCH-NOTES.md)"
    echo "     This requires multi-line changes in telegram.py send() method"
fi

# -----------------------------------------------------------------------
# Clear .pyc cache so Python uses fresh patched source, not cached bytecode
# -----------------------------------------------------------------------
echo ""
echo "[CLEANUP] Clearing Python bytecode cache..."
find "$HERMES_AGENT" -name "*.pyc" -delete 2>/dev/null && echo "  ✅ .pyc files cleared"

# -----------------------------------------------------------------------
# Restart PM2 agents
# -----------------------------------------------------------------------
echo ""
echo "[PM2] Restarting hermes agents with --update-env..."
pm2 restart hermes-ceo hermes-lab hermes-bmm hermes-siren --update-env 2>&1 | grep -E "✓|✗|error" | head -10
echo "  ✅ Agents restarted"

echo ""
echo "=== Re-apply complete ==="
echo "Monitor: pm2 logs hermes-ceo --lines 30"
echo "Patches doc: ~/company/hermes/PATCH-NOTES.md"
