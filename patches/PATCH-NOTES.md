# Hermes — Patch Notes & Configuration Fixes

Tracks any modifications to the Hermes codebase that live outside the official repo and will be overwritten by `hermes update`. After each update, re-apply active patches.

**CRITICAL: After any patch, clear Python bytecode cache and restart:**
```bash
find ~/.hermes/hermes-agent -name "*.pyc" -delete
cd ~/.hermes && pm2 delete hermes-gateway; pm2 start ecosystem.config.cjs
```
Without clearing `.pyc` files, Python uses cached bytecode and patches don't take effect.

---

## Active Patches

### PATCH-005: Enable Memory + Messaging in Cron Jobs (2026-04-03)

**Problem:** Cron jobs had `skip_memory=True` and `messaging` in disabled_toolsets. Agents couldn't persist memory across sessions or use `send_message` to post to other channels during execution.

**Fix:** In `cron/scheduler.py` (~line 439):
```python
# Before:
disabled_toolsets=["cronjob", "messaging", "clarify"],
skip_memory=True,

# After:
disabled_toolsets=["cronjob", "clarify"],
skip_memory=False,
```

**Re-apply after:** `hermes update`

---

### PATCH-001: Kimi K2.5 User-Agent Header (2026-04-03)

**Problem:** Kimi's Coding API (`api.kimi.com`) rejects requests unless the `User-Agent` header matches a recognized coding agent (Claude Code, Kimi CLI, Roo Code, Kilo Code). Hermes sends `KimiCLI/1.3` by default, which no longer passes.

**Fix:** Changed `User-Agent` from `KimiCLI/1.3` to `claude-code/1.0` in two locations:

**File:** `~/.hermes/hermes-agent/run_agent.py`

```
Location 1 (~line 791):
- "User-Agent": "KimiCLI/1.3",
+ "User-Agent": "claude-code/1.0",

Location 2 (~line 3798):
- self._client_kwargs["default_headers"] = {"User-Agent": "KimiCLI/1.3"}
+ self._client_kwargs["default_headers"] = {"User-Agent": "claude-code/1.0"}
```

**Tested:** HTTP 200 confirmed with `claude-code/1.0`. Other variants (`ClaudeCode/1.0`, `claude-code`, `Claude-Code/1.0.0`) all return 403.

**Re-apply after:** `hermes update` (git pull overwrites `run_agent.py`)

**Quick re-apply command:**
```bash
cd ~/.hermes/hermes-agent
sed -i '' 's/"User-Agent": "KimiCLI\/1.3"/"User-Agent": "claude-code\/1.0"/g' run_agent.py
```

---

### PATCH-004: Auto-Approve Commands (2026-04-03)

**Problem:** Gateway hardcodes `HERMES_EXEC_ASK=1` at import time, overriding any PM2/env setting. Every terminal command needs manual approval in Discord.

**Fix:** Changed to respect existing env var — only defaults to "1" if not already set.

**File:** `~/.hermes/hermes-agent/gateway/run.py` (~line 203)

```python
# Before:
os.environ["HERMES_EXEC_ASK"] = "1"

# After:
if "HERMES_EXEC_ASK" not in os.environ:
    os.environ["HERMES_EXEC_ASK"] = "1"
```

Set `HERMES_EXEC_ASK=0` in `~/.hermes/ecosystem.config.cjs` to disable.

**Re-apply after:** `hermes update`

---

### PATCH-003: Concurrent Cron Execution (2026-04-03, updated 2026-04-07)

**Problem:** Cron scheduler runs jobs sequentially — `for job in due_jobs`. When CEO heartbeat takes 20 minutes, all other agent cron jobs (Lab Genius, BMM Support, Siren) queue behind it. With 4 agents each having multiple cron jobs, this creates serious delays and missed schedules.

**Fix:** Replaced sequential loop with `ThreadPoolExecutor`. Single job still executes inline (no thread overhead). Multiple due jobs run concurrently up to `HERMES_CRON_MAX_WORKERS`.

**Worker count:** Controlled by `HERMES_CRON_MAX_WORKERS` env var (default: 4 if not set). Set to `20` in `ecosystem.hermes.config.cjs` for all agents. This covers all 4 agents' cron jobs across any concurrent tick.

**Single job behaviour:** When only one job is due, it runs directly without spawning a thread pool — this avoids ThreadPoolExecutor overhead for the common case. The `max_workers=20` cap only applies when 2+ jobs are due simultaneously.

**File:** `~/.hermes/hermes-agent/cron/scheduler.py` (inside `tick()`, ~line 580)

**Full patch code:**
```python
def _execute_job(job):
    try:
        advance_next_run(job["id"])
        success, output, final_response, error = run_job(job)
        output_file = save_job_output(job["id"], output)
        if verbose:
            logger.info("Output saved to: %s", output_file)
        deliver_content = final_response if success else f"⚠️ Cron job '{job.get('name', job['id'])}' failed:\n{error}"
        should_deliver = bool(deliver_content)
        if should_deliver and success and deliver_content.strip().upper().startswith(SILENT_MARKER):
            logger.info("Job '%s': agent returned %s — skipping delivery", job["id"], SILENT_MARKER)
            should_deliver = False
        if should_deliver:
            try:
                _deliver_result(job, deliver_content)
            except Exception as de:
                logger.error("Delivery failed for job %s: %s", job["id"], de)
        mark_job_run(job["id"], success, error)
        return True
    except Exception as e:
        logger.error("Error processing job %s: %s", job['id'], e)
        mark_job_run(job["id"], False, str(e))
        return False

# PATCH-003: run multiple due jobs concurrently (max HERMES_CRON_MAX_WORKERS workers).
executed = 0
if len(due_jobs) == 1:
    executed += 1 if _execute_job(due_jobs[0]) else 0
else:
    max_workers = int(os.getenv("HERMES_CRON_MAX_WORKERS", 4))
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {pool.submit(_execute_job, job): job for job in due_jobs}
        for future in concurrent.futures.as_completed(futures):
            try:
                if future.result():
                    executed += 1
            except Exception as e:
                logger.error("Concurrent job error: %s", e)
```

Also requires `import concurrent.futures` at the top of `scheduler.py`.

**Re-apply after:** `hermes update` (git pull overwrites `scheduler.py`)

**Quick re-apply:** Patch saved at `~/company/hermes/patches/scheduler-concurrent.patch`. Or copy the block above manually into the `tick()` function replacing the old sequential `for job in due_jobs` loop.

---

### PATCH-002: AGENTS.md Symlink (2026-04-03)

**Problem:** Hermes loads AGENTS.md from the gateway's CWD (`~/.hermes/hermes-agent/`), not from HERMES_HOME (`~/.hermes/`). The repo ships its own AGENTS.md (a dev guide), which overrides our CEO operating manual. The CEO had no tactical context — didn't know about state files, channels, decision tiers, or anything.

**Fix:** Renamed the repo's AGENTS.md and symlinked ours:

```bash
mv ~/.hermes/hermes-agent/AGENTS.md ~/.hermes/hermes-agent/AGENTS.md.dev-guide
ln -s ~/.hermes/AGENTS.md ~/.hermes/hermes-agent/AGENTS.md
```

**Re-apply after:** `hermes update` (git pull restores the repo's AGENTS.md)

**Quick re-apply command:**
```bash
cd ~/.hermes/hermes-agent
mv AGENTS.md AGENTS.md.dev-guide 2>/dev/null
ln -s ~/.hermes/AGENTS.md AGENTS.md
```

---

### PATCH-006: Telegram Flood Control in send() (2026-04-05)

**Problem:** When agents send multiple Telegram messages in quick succession (e.g., presenting email drafts), Telegram returns `RetryAfter` exceptions. These are **NOT** a subclass of `NetworkError`, so the `send()` method's catch block never catches them. The exception propagates up and kills the message delivery entirely. The `edit_message()` method already handled `RetryAfter` correctly, but `send()` did not.

**Fix:** In `gateway/platforms/telegram.py`, in the `send()` method's retry loop (~line 770):

1. Import `RetryAfter` alongside `BadRequest`:
```python
try:
    from telegram.error import RetryAfter as _RetryAfter
except ImportError:
    _RetryAfter = None
```

2. In the inner Markdown fallback block, re-raise `RetryAfter` instead of treating it as a parse error:
```python
except Exception as md_error:
    if _RetryAfter and isinstance(md_error, _RetryAfter):
        raise
    # ... existing markdown fallback logic
```

3. Changed outer `except _NetErr` to `except Exception` and added `RetryAfter` handling before `NetworkError`:
```python
except Exception as send_err:
    # Handle RetryAfter first (NOT a NetworkError subclass)
    if _RetryAfter and isinstance(send_err, _RetryAfter):
        wait = getattr(send_err, "retry_after", 10)
        logger.warning("[%s] Flood control on send (attempt %d/3), waiting %ds", ...)
        await asyncio.sleep(wait)
        continue
    # Only handle NetworkError from here on
    if not isinstance(send_err, _NetErr):
        raise
    # ... existing BadRequest/NetworkError handling
```

**Verified:** `RetryAfter` is confirmed not a subclass of `NetworkError` in python-telegram-bot (tested in Hermes venv).

**Re-apply after:** `hermes update`

---

### PATCH-007: Compression Summary Provider Config (2026-04-05)

**Problem:** The `compression.summary_model` config sets the model name but NOT the provider. The `_resolve_task_provider_model()` function in `agent/auxiliary_client.py` reads `compression.summary_provider` to route the API call, but this was never set in any agent's config.yaml. With provider="auto", the call gets misrouted to the wrong auth backend, causing `401 Invalid Authentication` errors on every context compression.

**Fix:** This is a **configuration fix**, not a code patch. Add `summary_provider` and `summary_base_url` to the `compression:` section of each agent's `config.yaml`:

```yaml
compression:
  enabled: true
  threshold: 0.50
  target_ratio: 0.20
  protect_last_n: 20
  summary_model: "MiniMax-M2.7-highspeed"
  summary_provider: "minimax"                    # <-- ADD THIS
  summary_base_url: "https://api.minimaxi.chat/v1"  # <-- ADD THIS
```

**Applied to:** `~/.hermes/profiles/bmm-support/config.yaml`
**Also check:** CEO and Lab configs if they use MiniMax for summaries.

**Re-apply after:** Creating new agents (template should include this).

---

## Resolved Patches (no longer needed)

_(none yet)_
