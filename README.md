# Hermes Growth Hacks

Patches and field manuals for running a zero-human, multi-agent fleet on Hermes.

---

## What This Is

Hermes is a multi-agent AI system. Out of the box, it runs one agent, one user, one gateway. Fine for experimentation. Not fine when you need five agents firing simultaneously — each with their own memory, Telegram bot, and cron schedule — with zero humans checking in.

This repo is the field manual we built for exactly that use case. Problems we hit, what they actually broke, and how we fixed them. Everything you need to replicate it.

---

## The Use Case

Zero-human lab operation. Multiple entities, multiple agents, no humans in the loop. Five agents running simultaneously:
- CEO agent — processes the world, writes findings to a shared brain
- BMM agent — handles customer support
- Siren agent — runs daily batch pipelines
- Lab agent — executes experiments
- Business Analyst — triggered on demand via mention

Each agent with its own profile, memory, Telegram topic, and cron schedule. All coordinated through shared brain files. None of them blocking each other.

---

## What's In Here

**MULTI-AGENT-FLEET-GUIDE.md** — The full field manual. Architecture, all 6 patches, the re-apply script, fleet coordination logic, what to do when it breaks after an update.

**THREAD.md** — The Twitter thread. Three versions: 3-tweet (blue tick), 10-tweet (standard), single-tweet. All aligned to the guide.

**patches/** — The re-apply script and individual patch files. Run after every `hermes update`:
```bash
bash patches/reapply-all-patches.sh
```

---

## The Problems We Solved

| Problem | What It Broke |
|---------|---------------|
| Sequential cron | CEO heartbeat (20 min) blocked all other agents. BMM missed hour triggers. Siren missed daily batches. |
| HERMES_EXEC_ASK="1" hardcoded | Cron jobs stopped dead waiting for a human who wasn't there. |
| skip_memory=True in cron | CEO writes to shared brain. Lab agent reads from it. Channel closes mid-cron. Lab runs on stale data. |
| messaging disabled in cron | Cron ran, nobody saw results. Workarounds needed just to deliver output. |
| Telegram RetryAfter not caught | Flood control fired, messages stopped, nobody knew why. Silent death. |
| Kimi API rejected User-Agent | Every Kimi API call failed silently. |

---

## The Architecture

One codebase (`hermes-agent/`) on disk. Each agent its own OS process with its own `HERMES_HOME` pointing to its own profile directory — Hermes's native multi-user isolation. Each profile = isolated memory, state, sessions, cron DB. Six PM2 entries, six cron schedulers, zero cross-blocking.

Each with its own Telegram bot in its own group/topic. Routing by mention pattern.

---

## The Six Patches

| # | Patch | File | Fix |
|---|-------|------|-----|
| 1 | User-Agent → `claude-code/1.0` | `run_agent.py` | Kimi API works |
| 2 | AGENTS.md symlink | `hermes-agent/AGENTS.md` | Your operating manual loads every cycle |
| 3 | ThreadPoolExecutor concurrent cron | `cron/scheduler.py` | Agents run in parallel, 20 workers max |
| 4 | `HERMES_EXEC_ASK = "0"` | `gateway/run.py` | Autonomous operation, no human in the loop |
| 5 | `skip_memory=False` + messaging enabled | `cron/scheduler.py` | Brain writes survive cron, results deliver to Telegram |
| 6 | Telegram `RetryAfter` caught explicitly | `gateway/platforms/telegram.py` | Flood control handled, messages delivered |

---

## Quick Start

```bash
# 1. Install Hermes once at ~/.hermes/hermes-agent
# 2. Create one profile per agent at ~/.hermes/profiles/<name>/
# 3. One Telegram bot per agent, each in its own group/topic
# 4. PM2 ecosystem config — one entry per agent with its own HERMES_HOME
# 5. After every hermes update:
bash patches/reapply-all-patches.sh
```

Zero humans. Five agents. One coordinated fleet.
