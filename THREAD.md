================================================================================
TWITTER/X THREAD — "How to Run a Zero-Human Agent Fleet on Hermes"
================================================================================
Blue tick version — ~2,500 char limit per tweet.
Casual/peer tone.
3-tweet thread.
================================================================================

🧵 1/3
We run a zero-human lab. Multiple entities, over 10 agents running simultaneously.

We hit a wall fast: Hermes ships configured for one agent. The moment you need a coordinated fleet — different agents with their own memory, own Telegram topic, own cron schedule — the defaults actively fight you.

Here's what broke and how we fixed it, from someone who actually had to make it work.

---

🧵 2/3
Problems we hit:

Cron ran sequentially. Our CEO heartbeat takes 20 minutes. Everything else — BMM customer responses, Siren's daily batch, knowledge extraction — queued behind it. Agents were missing their hour triggers because one job was eating the whole window.

Memory writes died mid-cron. CEO writes findings to a shared brain during its cycle. Downstream agents read from it. But default cron has skip_memory=True — that write channel closes before anything gets persisted. Downstream agents read stale data. Silent failure.

Results never showed up in Telegram. Default cron disables the messaging toolset. Cron ran, output was generated, nobody saw it. Had to build workarounds just to get the output delivered.

Telegram messages just stopped. No error, no warning. Turned out python-telegram-bot's RetryAfter exception isn't a subclass of NetworkError — the gateway's catch block never caught it. Flood control fired, messages died silently.

Every Kimi API call failed silently. The API rejects everything except whitelisted User-Agents. Hermes ships with one that isn't on the list.

---

🧵 3/3
The fix: one codebase, multiple isolated gateway processes.

Same hermes-agent/ on disk. Each gateway agent runs as its own OS process with its own HERMES_HOME — Hermes's native multi-user isolation. Each with its own Telegram bot in its own topic. Five full gateway agents (CEO, Lab, BMM, Siren, BA). Internal agents (Knowledge Extractor, Team State Engineer, Process Engineer, Epoch Evaluator) are in-memory workers spawned by the CEO's cron — no separate gateway needed for the lighter workloads.

Six patches: User-Agent fix / AGENTS.md symlink / ThreadPoolExecutor for concurrent cron (20 workers) / HERMES_EXEC_ASK=0 for autonomous operation / skip_memory=False + messaging enabled / Telegram RetryAfter caught explicitly.

Every Hermes update wipes the codebase. One re-apply script restores everything in seconds — idempotent.

Full field manual: github.com/PurposeGateway/Hermes-Growth-Hacks

================================================================================
SINGLE-TWEET VERSION
================================================================================

"We ran 10+ Hermes agents as a zero-human lab. The defaults break the moment you scale.
Here's the 6 patches and architecture that made it actually work."

================================================================================
