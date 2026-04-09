================================================================================
TWITTER/X THREAD — "How to Run a Zero-Human Agent Fleet on Hermes"
================================================================================
Post as a thread. Each numbered block = one tweet (within 280 chars each).
Structure: USE CASE → PROBLEMS (with impact) → FIX
================================================================================

THREAD START

🧵 1/
We run a zero-human lab. Multiple entities, multiple agents, zero humans checking in.

We needed 5 Hermes agents firing simultaneously — each with their own memory, Telegram bot, and cron schedule — all running autonomously.

What nobody tells you: Hermes's defaults assume one agent. The moment you scale past that, everything breaks in ways that look like bugs but are actually design assumptions.

---

🧵 2/
ISSUE 1: Sequential cron execution

The default tick() runs all due jobs one at a time. Our CEO heartbeat takes 20 minutes.

Impact: while the CEO heartbeat ran, every other agent's cron jobs queued behind it. BMM support missed its hour trigger. Siren missed its daily batch. The Lab agent never fired on schedule. Everything stacked up waiting for one job to finish.

---

🧵 3/
ISSUE 2: HERMES_EXEC_ASK = "1" hardcoded at startup

Hermes locks this to 1 on gateway boot — every command pauses waiting for human approval.

Impact: cron jobs running on a schedule stopped dead waiting for a human who wasn't there. The moment you need agents to run unattended, this breaks the entire autonomous operation model.

---

🧵 4/
ISSUE 3: skip_memory = True in cron (default)

Cron jobs run without access to the memory system by default.

Impact: Our CEO agent processes the world, writes findings to a shared brain. Other agents read from that brain during their own cycles. With skip_memory=True, that write channel closes during cron execution. The Lab agent runs on stale data. The whole coordination system fails silently.

---

🧵 5/
ISSUE 4: messaging disabled in cron (default)

The messaging toolset is blocked during cron execution.

Impact: agents couldn't send results to Telegram during job execution. Cron runs completed but nobody saw the output. We had to build workarounds to get results delivered at all.

---

🧵 6/
ISSUE 5: Telegram flood control swallowed silently

python-telegram-bot's RetryAfter exception is NOT a subclass of NetworkError. The gateway's catch block never caught it.

Impact: when agents sent messages rapidly, Telegram's flood control kicked in, RetryAfter fired, nobody caught it — messages just stopped sending. No error shown. No retry. Silent death.

---

🧵 7/
ISSUE 6: Kimi API User-Agent rejection

api.kimi.com rejects every User-Agent except a short list of whitelisted coding agents. Hermes ships with KimiCLI/1.3.

Impact: every API call to Kimi failed silently. No error shown. Agents just... didn't get responses. Diagnosing this was painful.

---

🧵 8/
THE FIX: One codebase, six isolated gateway processes.

Same hermes-agent/ install on disk. Each agent runs as a separate OS process with its own HERMES_HOME pointing to its own profile directory — Hermes's native multi-user isolation. Isolated memory, state, sessions, cron DB. No two agents can overwrite each other's state.

Each with its own Telegram bot in its own group/topic. Routing by mention pattern.

Six PM2 entries. Six processes. Six isolated HERMES_HOME values. The cron scheduler lives inside each process — so each agent's cron fires on its own schedule without blocking others.

---

🧵 9/
Then six patches:

1. User-Agent → claude-code/1.0 (Kimi API fix)
2. AGENTS.md symlink → loads your actual operating manual
3. ThreadPoolExecutor concurrent cron → agents run in parallel, 20 workers max
4. HERMES_EXEC_ASK=0 hardcoded → autonomous operation, no human in the loop
5. skip_memory=False + messaging enabled → brain writes survive cron, results deliver to Telegram
6. Telegram RetryAfter caught explicitly → flood control handled, messages delivered reliably

---

🧵 10/
Every Hermes update wipes the codebase and wipes all patches. We built a re-apply script that runs after every update, detects what's already applied, restores what isn't — in seconds. Idempotent by design.

Zero humans. Five agents. One coordinated fleet.

Full field manual with architecture, all patches, re-apply script, and detection patterns:

github.com/PurposeGateway/Hermes-Growth-Hacks

================================================================================
ALTERNATE OPENING HOOK (more punchy)
================================================================================

"We needed 5 Hermes agents running simultaneously — each with their own memory, Telegram bot, and cron schedule.

What nobody warns you: Hermes's defaults assume one agent. Everything breaks the moment you scale past that.

Here's the complete field manual — including the 6 patches nobody tells you about."

[CONTINUE FROM TWEET 2 ABOVE]

================================================================================
SINGLE-TWEET VERSION (280 chars)
================================================================================

"Hermes breaks past one agent. Not a bug — design assumptions.
We needed 5 agents, 6 patches, concurrent cron, shared brain, zero humans.
Here's the full field manual: github.com/PurposeGateway/Hermes-Growth-Hacks"

================================================================================
