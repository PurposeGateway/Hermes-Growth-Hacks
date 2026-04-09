================================================================================
TWITTER/X THREAD — "How to Run a Zero-Human Agent Fleet on Hermes"
================================================================================
Blue tick version — ~2,500 char limit per tweet.
Casual/peer tone — like sharing with fellow hackers.
3-tweet thread.
================================================================================

🧵 1/3
We needed to run 5 Hermes agents simultaneously — each with their own memory, Telegram bot, and cron schedule, zero humans checking in.

What nobody warns you: Hermes's defaults are built for one agent. The moment you scale past that, everything breaks in ways that look like bugs but are actually design assumptions.

Here's the field manual nobody wrote.

---

🧵 2/3
Problems we hit and what they actually broke:

Sequential cron — CEO heartbeat took 20 min, blocked every other agent's jobs. BMM missed its hour trigger. Siren missed daily batches. Everything stacked behind one job.

skip_memory=True in cron — CEO writes to shared brain, downstream agents read from it. That channel closes mid-cron. Lab agent runs on stale data. Silent failure.

messaging blocked in cron — cron runs completed, nobody saw results. Had to build workarounds to deliver output at all.

HERMES_EXEC_ASK hardcoded to 1 — cron jobs stopped dead waiting for a human who wasn't there.

Telegram RetryAfter not caught — flood control fired, messages stopped, nobody knew why.

Kimi API rejected the User-Agent — every call failed silently, agents just didn't get responses.

---

🧵 3/3
The fix: one codebase, six isolated gateway processes.

Same hermes-agent/ on disk. Each agent its own OS process + profile directory (Hermes's native multi-user isolation). Each with its own Telegram bot in its own topic. Six PM2 entries, six cron schedulers, zero cross-blocking.

Six patches: User-Agent→claude-code/1.0 / AGENTS.md symlink / ThreadPoolExecutor concurrent cron (20 workers) / HERMES_EXEC_ASK=0 / skip_memory=False+messaging enabled / RetryAfter caught explicitly.

Every update wipes the codebase. One re-apply script restores everything in seconds — idempotent.

Zero humans. Five agents. One coordinated fleet.

Full guide + re-apply script:
github.com/PurposeGateway/Hermes-Growth-Hacks

================================================================================
SINGLE-TWEET VERSION
================================================================================

"Hermes breaks past one agent. Not a bug — design assumptions.
We needed 5 agents, 6 patches, concurrent cron, shared brain, zero humans.
Full field manual: github.com/PurposeGateway/Hermes-Growth-Hacks"

================================================================================
