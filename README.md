# Hermes Growth Hacks

Field manuals, patches, and operational guides for stretching Hermes to its logical conclusion: a zero-human, multi-agent fleet.

---

## What's Here

**MULTI-AGENT-FLEET-GUIDE.md** — The main field manual. Everything you need to run 5+ Hermes agents as a coordinated fleet with no human in the loop. Architecture, all 6 patches, the re-apply script, fleet coordination logic.

**THREAD.md** — The Twitter/X thread. Three versions: full 10-tweet thread, alternate opening hook, single-tweet version. All aligned to the guide.

**patches/** — The re-apply script and individual patch files. Run `patches/reapply-all-patches.sh` after every `hermes update`.

---

## The Six Patches

| # | Patch | File | Why |
|---|-------|------|-----|
| 1 | User-Agent → `claude-code/1.0` | `run_agent.py` | Kimi API rejects everything else |
| 2 | AGENTS.md symlink | `hermes-agent/AGENTS.md` | Loads your operating manual, not the repo dev guide |
| 3 | Concurrent cron (ThreadPoolExecutor) | `cron/scheduler.py` | Sequential cron blocked all agents — now they run in parallel |
| 4 | `HERMES_EXEC_ASK = "0"` | `gateway/run.py` | Hardcoded approval breaks autonomous cron |
| 5 | `skip_memory=False` + messaging enabled | `cron/scheduler.py` | Default cron severs both memory and message channels |
| 6 | Telegram `RetryAfter` flood control | `gateway/platforms/telegram.py` | Not a NetworkError subclass — silently swallowed messages |

---

## Quick Start

```bash
# 1. Install Hermes once
# 2. Create one profile per agent at ~/.hermes/profiles/<name>/
# 3. One Telegram bot per agent, each in its own topic
# 4. PM2 ecosystem config — one entry per agent with its own HERMES_HOME
# 5. Run the re-apply script after every update:
bash ~/company/hermes/patches/reapply-all-patches.sh
```

Zero humans. Five agents. One coordinated fleet.

See **MULTI-AGENT-FLEET-GUIDE.md** for the full field manual.
