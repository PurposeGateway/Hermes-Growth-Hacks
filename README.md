# Hermes Growth Hacks

Patches and field manuals for running a zero-human, multi-agent fleet on Hermes. This repo grows as we build — each problem we solve goes here.

---

## What This Is

We're a zero-human lab. Multiple entities, over 10 agents running simultaneously — full gateway agents for the heavy workloads (CEO, Lab, BMM, Siren, Business Analyst), in-memory workers spawned by cron for lighter continuous tasks (Knowledge Extractor, Team State Engineer, Process Engineer, Epoch Evaluator).

This repo is where we document what we build, what breaks, and how we fix it. Not a product — a working lab notebook made public.

---

## The Use Case

Zero-human lab operation. Multiple entities, multiple agents, no humans checking in.

Five gateway agents — each with their own profile, memory, Telegram topic, and cron schedule:
- CEO agent — processes the world, writes findings to a shared brain
- BMM agent — handles customer support
- Siren agent — runs daily batch pipelines
- Lab agent — executes experiments
- Business Analyst — triggered on demand via mention

Plus internal cron agents (Knowledge Extractor, Team State Engineer, Process Engineer, Epoch Evaluator, Wiki Keeper) — spawned as in-memory workers by the CEO's cron jobs. These don't need their own gateway since they're lightweight workers, not standalone agents.

Each agent coordinates through shared brain files. None of them blocking each other.

---

## What's In Here

**MULTI-AGENT-FLEET-GUIDE.md** — The field manual. Architecture, all 6 patches, the re-apply script, fleet coordination logic, what to do when it breaks after an update.

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

One codebase (`hermes-agent/`) on disk. Two types of agents:

**Gateway agents** — full separate OS processes, each with its own `HERMES_HOME`. Five of these (CEO, Lab, BMM, Siren, BA). Each has its own profile directory, isolated memory/state/sessions/cron DB, own Telegram bot, own cron scheduler embedded in the gateway process. Six PM2 entries, six processes, zero cross-blocking.

**Internal cron agents** — in-memory workers spawned by the CEO's cron jobs. Knowledge Extractor, Team State Engineer, Process Engineer, Epoch Evaluator, Wiki Keeper. These are instantiated by the AIAgent class during cron execution, not separate gateway processes. They share the CEO's HERMES_HOME memory system but each has its own isolated working state via profile-scoped directories.

Each gateway agent with its own Telegram bot in its own group/topic. Routing by mention pattern.

---

## The Six Patches

| # | Patch | File | Fix |
|---|-------|------|-----|
| 1 | User-Agent → `claude-code/1.0` | `run_agent.py` | Kimi API works |
| 2 | ThreadPoolExecutor concurrent cron | `cron/scheduler.py` | Agents run in parallel, 20 workers max |
| 3 | ThreadPoolExecutor concurrent cron | `cron/scheduler.py` | Agents run in parallel, 20 workers max |
| 4 | `HERMES_EXEC_ASK = "0"` | `gateway/run.py` | Autonomous operation, no human in the loop |
| 5 | `skip_memory=False` + messaging enabled | `cron/scheduler.py` | Brain writes survive cron, results deliver to Telegram |
| 6 | Telegram `RetryAfter` caught explicitly | `gateway/platforms/telegram.py` | Flood control handled, messages delivered |

---

## Quick Start

```bash
# 1. Install Hermes once at ~/.hermes/hermes-agent
# 2. Create one profile per gateway agent at ~/.hermes/profiles/<name>/
# 3. One Telegram bot per gateway agent, each in its own group/topic
# 4. PM2 ecosystem config — one entry per gateway agent with its own HERMES_HOME
# 5. After every hermes update:
bash patches/reapply-all-patches.sh
```

---

More to come as we build. Watch this space.
