================================================================================
TWITTER/X THREAD — "How to Run a Zero-Human Agent Fleet on Hermes"
================================================================================
Post as a thread. Each numbered block = one tweet (within 280 chars each).
================================================================================

THREAD START

🧵 1/10
Most people set up Hermes, get one agent running, and call it done.

What nobody warns you: the moment you need five agents working as a team — each with their own memory, Telegram bot, and cron schedule — the defaults fall apart.

This is the field manual nobody wrote.

---

🧵 2/10
Hermes was designed around one assumption: one agent, one user, one gateway.

Your zero-human lab needs five agents firing simultaneously, sharing context, delivering results, running on schedules with no human in the loop.

That is not a bug. It is a design gap. And every gap has a patch.

---

🧵 3/10
The fleet architecture: one codebase, five isolated gateways.

Same hermes-agent/ install on disk. Each agent gets its own profile directory (Hermes's native multi-user system). Each profile = isolated memory, state, sessions, cron DB.

No two agents can overwrite each other's state. Ever.

---

🧵 4/10
One Telegram bot per agent. Each bot lives in its own group/topic.

CEO agent → your direct messages
BMM agent → BMM customer topic
Lab agent → lab topic
BA agent → triggered by the word "analyst"

Routing by mention pattern. Clean separation. No cross-talk.

---

🧵 5/10
Here is what the defaults get wrong — and why each patch exists:

PATCH 1: User-Agent
api.kimi.com rejects everything except claude-code/1.0. Swap it in two places in run_agent.py.

PATCH 2: AGENTS.md symlink
Gateway loads from CWD. Symlink it to your actual operating manual so it loads every cycle.

---

🧵 6/10
PATCH 3: Concurrent cron (THE BIG ONE)
Default tick() runs jobs sequentially. A 20-min CEO heartbeat blocked ALL other agents.

Fix: ThreadPoolExecutor runs due jobs in parallel. With 20 workers, five agents can all fire simultaneously without blocking each other.

PATCH 4: HERMES_EXEC_ASK = "0"
Hardcoded approval prompt breaks autonomous cron. Force it to auto-approve so jobs run without stopping for a human.

---

🧵 7/10
PATCH 5: skip_memory=False + messaging enabled
Default cron blocks both. That means: agents can't write memory mid-cron, and can't send Telegram messages during execution.

In a team, the CEO writes to the brain. Downstream agents read from it. If that channel closes during cron execution, your lab agent runs on stale data.

---

🧵 8/10
PATCH 6: Telegram RetryAfter flood control
python-telegram-bot's RetryAfter is NOT a subclass of NetworkError. The gateway was swallowing flood control exceptions silently. Messages just... stopped sending.

Fix: catch RetryAfter explicitly, wait the specified duration, retry.

---

🧵 9/10
The re-apply script is the key to the whole system.

Every Hermes update overwrites the codebase and wipes these changes. Run one script after every update:

bash ~/company/hermes/patches/reapply-all-patches.sh

Patches are the only fragile part. The architecture — profiles, PM2, Telegram bots — survives updates intact.

---

🧵 10/10
Give this to an agent and tell it to implement it:

1. Install Hermes once at ~/.hermes/hermes-agent
2. Create one profile per agent at ~/.hermes/profiles/<name>/
3. One Telegram bot per agent in its own topic
4. PM2 ecosystem config: HERMES_HOME, TELEGRAM_BOT_TOKEN, HERMES_CRON_MAX_WORKERS=20, HERMES_EXEC_ASK=0
5. Run the patch re-apply script after every Hermes update
6. Stagger cron schedules
7. Share context via shared brain files; per-profile memory for agent-local state

Zero humans. Five agents. One coordinated fleet.

---
================================================================================
ALTERNATE OPENING HOOK (more punchy, shorter)
================================================================================

"Hermes breaks the moment you scale past one agent.

Not because it's bad software — because it wasn't designed for a zero-human lab running five agents simultaneously.

Here's the complete field manual for building an agent fleet on Hermes that actually works — including the six patches nobody tells you about."

[CONTINUE FROM TWEET 3 ABOVE]

---
================================================================================
SINGLE-TWEET VERSION (280 chars)
================================================================================

"Hermes breaks past one agent. Not a bug — a design gap.
Here's the complete field manual for a zero-human fleet: 5 agents, 5 bots, concurrent cron, shared brain, no humans.
6 patches. 1 re-apply script. Full guide below."

================================================================================
