# Thread: How to Run a Multi-Agent Team on Hermes (No Humans Required)

---

**The Problem Nobody Warns You About**

Most people set up Hermes, get one agent working, and stop there. Fine. But what happens when you need five agents running simultaneously — each with their own memory, their own Telegram bot, their own cron schedule, all operating as a coordinated fleet?

Hermes was not designed for that out of the box. The defaults assume one agent, one user, one gateway. The moment you scale past that, everything starts breaking in ways that look like bugs but are actually design assumptions you have collided with.

This is the guide I wish existed. Not a tutorial — a field manual. Everything you need to know to build a functioning zero-human agent team on Hermes, why each decision was made, and what to do when it falls apart after an update.

---

## The Architecture: One Codebase, Five Independent Gateways

The entire fleet runs from a single `hermes-agent` installation on disk. But each agent is a **separate OS process** with its own isolated environment:

```
~/.hermes/hermes-agent/     ← shared codebase (read-only to agents)
  ├── gateway/run.py
  ├── cron/scheduler.py
  ├── run_agent.py
  └── ...

~/.hermes/                   ← CEO profile (hermes-ceo)
~/.hermes/profiles/
  ├── lab-genius/            ← Lab agent (hermes-lab)
  ├── bmm-support/           ← BMM agent (hermes-bmm)
  ├── siren/                 ← Siren agent (hermes-siren)
  └── business-analyst/       ← BA agent (hermes-ba)
```

Each agent gets its own profile directory. This is not a subdirectory convention — it is how Hermes natively supports multiple users. Every agent's `HERMES_HOME` points to its own profile. Memory, state files, sessions, skills, cron database — all isolated. No two agents can overwrite each other's state.

**The critical constraint — why each agent needs its own PM2 entry:**

The cron scheduler runs *inside* each gateway process. When a PM2 entry starts with `HERMES_HOME=~/.hermes/profiles/bmm-support`, that entire process — including its cron scheduler — IS the BMM agent. `HERMES_HOME` is set once, before Python starts, via the PM2 `env` block. It cannot be changed mid-process.

There is no mechanism to "run a cron job from within an existing gateway AND set the agent's home to a subdirectory." The gateway process is bound to one `HERMES_HOME` for its entire lifetime. The cron scheduler embedded in that process schedules jobs for *that* agent's profile only.

**In practice:** Six PM2 entries, six processes, six isolated `HERMES_HOME` values. Each process has its own cron scheduler. The fleet coordinates through shared brain files — not through one process managing another's cron.

PM2 manages the fleet via ecosystem config. Each entry is a full gateway instance:

```javascript
// ecosystem.hermes.config.cjs
module.exports = {
  apps: [
    {
      name: 'hermes-ceo',
      cwd: '~/.hermes/hermes-agent',
      script: './venv/bin/python',
      args: '-m gateway.run --verbose',
      env: {
        HERMES_HOME: '~/.hermes',
        HERMES_EXEC_ASK: '0',
        HERMES_CRON_MAX_WORKERS: '20',
        TELEGRAM_BOT_TOKEN: '<ceo-bot-token>',
      },
    },
    {
      name: 'hermes-bmm',
      cwd: '~/.hermes/hermes-agent',
      script: './venv/bin/python',
      args: '-m gateway.run --verbose',
      env: {
        HERMES_HOME: '~/.hermes/profiles/bmm-support',
        HERMES_EXEC_ASK: '0',
        HERMES_CRON_MAX_WORKERS: '20',
        TELEGRAM_BOT_TOKEN: '<bmm-bot-token>',
      },
    },
    // ... one entry per agent
  ],
};
```

`HERMES_EXEC_ASK: '0'` means each gateway auto-approves all commands. No human in the loop interrupting cron execution. This is intentional — when an agent runs on a schedule, it must be able to act autonomously. The trade-off is that interactive use also auto-approves, which is acceptable as long as access to the bot is controlled.

`HERMES_CRON_MAX_WORKERS: '20'` is the concurrency limit for the cron scheduler. More on why this matters below.

---

## The Five Patches (And Why Each One Is Necessary)

Every `hermes update` overwrites the agent codebase. Every overwrite wipes these changes. You need a re-apply script that runs after every update. Here is the full picture of what each patch does and why.

### PATCH-001: Kimi User-Agent → `claude-code/1.0`

**File:** `hermes-agent/run_agent.py`

**The problem:** `api.kimi.com` — one of the model providers Hermes uses — rejects every User-Agent string except a short list of whitelisted coding agents. The default Hermes User-Agent (`KimiCLI/1.3`) is not on that list. Every API call fails silently.

**The fix:** Replace the User-Agent with `claude-code/1.0`, which is the only confirmed working value. Applied in two locations in `run_agent.py` because the header is set in two different code paths.

```python
# Before
"User-Agent": "KimiCLI/1.3"

# After
"User-Agent": "claude-code/1.0"
```

**Detection pattern:**
```bash
grep '"User-Agent": "KimiCLI/1.3"' run_agent.py
```

---

### PATCH-002: AGENTS.md Symlink

**File:** `hermes-agent/AGENTS.md` → `~/.hermes/AGENTS.md`

**The problem:** Hermes loads `AGENTS.md` from its CWD (the `hermes-agent/` directory). The default file in the repo is a dev guide — not your operating manual. You need your CEO manual, your SOUL, your domain knowledge loaded for every conversation.

**The fix:** Symlink `hermes-agent/AGENTS.md` to your `~/.hermes/AGENTS.md`. The gateway loads the symlink, follows it, and your actual operating manual loads every time.

```bash
# Before (repo file loaded):
hermes-agent/AGENTS.md  →  (repo's dev guide)

# After (your manual loaded):
hermes-agent/AGENTS.md  →  ~/.hermes/AGENTS.md  →  (your CEO SOUL + AGENTS)
```

**Detection pattern:**
```bash
[ -L hermes-agent/AGENTS.md ] && [ "$(readlink hermes-agent/AGENTS.md)" = "$HOME/.hermes/AGENTS.md" ]
```

---

### PATCH-003: Concurrent Cron Execution

**File:** `hermes-agent/cron/scheduler.py`

**The problem:** The default `tick()` function runs all due cron jobs sequentially. A 20-minute CEO heartbeat would block all other agents from running until it finished. With multiple agents each scheduling jobs, this becomes a cascade of missed windows and backlogged queues.

**The fix:** Refactor `tick()` to run due jobs concurrently using `ThreadPoolExecutor`. Single jobs skip the pool overhead (no thread creation tax). Multiple jobs run in parallel, up to `HERMES_CRON_MAX_WORKERS` workers (default 20).

```python
# Before
for job in due_jobs:
    execute_sequentially(job)  # one at a time

# After
if len(due_jobs) == 1:
    _execute_job(due_jobs[0])
else:
    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {pool.submit(_execute_job, job): job for job in due_jobs}
        for future in concurrent.futures.as_completed(futures):
            # collect results as they complete
```

**Why 20 workers:** A fleet with 5 agents, each scheduling multiple jobs per hour, can have 10-15 jobs due in the same tick window. 20 workers gives headroom without excessive overhead. Tune down if your server is memory-constrained. Tune up if your fleet scales.

**Detection pattern:**
```bash
grep "_execute_job" hermes-agent/cron/scheduler.py
```

---

### PATCH-004: HERMES_EXEC_ASK = "0"

**File:** `hermes-agent/gateway/run.py`

**The problem:** Hermes hardcodes `HERMES_EXEC_ASK=1` on gateway startup, which pauses execution waiting for human approval. Cron jobs running on a schedule cannot wait for a human. Auto-approval is required for autonomous operation.

**The fix:** Hardcode `os.environ["HERMES_EXEC_ASK"] = "0"` immediately after the line that sets it to 1. This overrides the default before any agent thread starts.

```python
# In gateway/run.py, near the top:
os.environ["HERMES_EXEC_ASK"] = "1"  # Hermes default
# ... later, force override:
os.environ["HERMES_EXEC_ASK"] = "0"  # Always auto-approve
```

**What you give up:** Interactive gateway use also auto-approves. This is why access to the Telegram bot must be restricted — you control who can trigger it. For personal use with a private bot, this is fine.

**Detection pattern:**
```bash
grep 'os.environ\["HERMES_EXEC_ASK"\] = "0"' hermes-agent/gateway/run.py
```

---

### PATCH-005: skip_memory=False + Messaging Toolset Enabled

**File:** `hermes-agent/cron/scheduler.py`

**The problem:** Two separate issues:

1. **skip_memory=True** (default in cron): Cron jobs run without access to the memory system. In a multi-agent fleet, the CEO agent writes context to memory that downstream agents read. With `skip_memory=True`, that channel is closed during cron execution.

2. **messaging in disabled_toolsets** (default in cron): The messaging toolset is blocked during cron. Agents cannot send Telegram messages during job execution — which means cron results never reach the chat unless delivered through a separate mechanism.

3. **HERMES_CRON_TIMEOUT=600** (default, 10 minutes): Too short for long-running CEO heartbeats. Bumped to 1200s (20 minutes).

**The fix:**
```python
# Before
disabled_toolsets=["cronjob", "messaging", "clarify"],
skip_memory=True,

# After
disabled_toolsets=["cronjob", "clarify"],
skip_memory=False,
_cron_timeout = float(os.getenv("HERMES_CRON_TIMEOUT", 1200))
```

**Why this matters in a team context:** The CEO agent processes the world (Wiki, Epoch), writes findings to memory, and those outputs are read by the Lab agent when it runs its own heartbeat. If the CEO's cron run cannot write memory, the Lab agent works from stale data. The messaging toolset is how the agent delivers results directly to the Telegram topic without going through a delivery queue.

**Detection pattern:**
```bash
grep "skip_memory=False" hermes-agent/cron/scheduler.py
grep 'disabled_toolsets=\["cronjob", "clarify"\]' hermes-agent/cron/scheduler.py
grep 'HERMES_CRON_TIMEOUT", 1200' hermes-agent/cron/scheduler.py
```

---

### PATCH-006: Telegram RetryAfter Flood Control

**File:** `hermes-agent/gateway/platforms/telegram.py`

**The problem:** The `python-telegram-bot` library's `RetryAfter` exception is **not a subclass of `NetworkError`**. The gateway had a catch-all `except NetworkError` block that did not handle `RetryAfter`. When Telegram triggered flood control, the exception was silently swallowed — messages stopped sending and nobody knew why.

**The fix:** Import `RetryAfter` separately, catch it explicitly before the `NetworkError` handler, and wait the specified `retry_after` duration before retrying:

```python
from telegram.error import RetryAfter as _RetryAfter
# ...
except Exception as send_err:
    if _RetryAfter and isinstance(send_err, _RetryAfter):
        wait = getattr(send_err, "retry_after", 10)
        await asyncio.sleep(wait)
        continue  # retry the send
    if not isinstance(send_err, _NetErr):
        raise  # re-raise non-network errors
    # ... network error handling
```

**Detection pattern:**
```bash
grep "_RetryAfter" hermes-agent/gateway/platforms/telegram.py
```

---

## The Re-Apply Script

Every `hermes update` wipes the codebase. You need a script that restores all patches in one run. Place it at `~/company/hermes/patches/reapply-all-patches.sh` and run it after every update:

```bash
bash ~/company/hermes/patches/reapply-all-patches.sh
```

The script:
1. Detects whether each patch is already applied (avoids double-application)
2. Uses `git apply` where possible, falls back to `sed` for single-line changes
3. Clears Python bytecode cache (`.pyc` files)
4. Restarts all PM2 agents with `--update-env`

The patch file (`scheduler-concurrent.patch`) is a standard `git diff` and can be applied with `git apply`. Single-line fixes use `sed` for reliability when the surrounding context may have shifted.

**Patch detection logic** — each patch section of the script:
- If the pattern already exists → patch is applied, skip
- If not → apply it
- If the patch file is missing → warn and instruct manual application

This means running the script multiple times is safe. Idempotent by design.

---

## How the Fleet Coordinates

Five agents, five bots, five Telegram topics. How do they work as a team?

**The routing principle:** Each agent owns its topic. The primary agent listens to direct messages and a lab-level topic. The BMM agent listens to the BMM customer topic. Each agent's `TELEGRAM_MENTION_PATTERNS` env var controls which keywords trigger it — so "analyst" routes to the BA agent regardless of which topic the message appears in.

**The memory sharing principle:** Agents share context through the **brain system** — a shared set of knowledge files that agents read and write during their heartbeats. The CEO agent mines the web and writes findings to the brain. Other agents read from the brain during their own cycles. Memory isolation (per-profile) applies to the agent's own working state — the brain files are shared explicitly.

**The cron coordination principle:** Jobs are staggered by setting different `cron` expressions per agent. The CEO heartbeat runs on a 30-minute cycle. The BMM agent runs every hour. The Lab agent runs on demand or on a trigger. With `HERMES_CRON_MAX_WORKERS=20`, simultaneous due jobs do not block each other.

---

## What to Do When It Breaks After an Update

1. **Run the re-apply script first.** Most failures are just patches not restored.
2. **Check PM2 logs:** `pm2 logs hermes-ceo --lines 50`
3. **Verify patches:** Run each grep detection pattern from the script manually.
4. **Check the Hermes changelog** if available — update may have changed a file structure the patch depends on.
5. **If a patch no longer applies:** Check `~/company/hermes/PATCH-NOTES.md` for full inline code blocks for manual application.

The system is designed so that **patches are the only thing that needs maintenance**. The underlying architecture — profiles, PM2, Telegram bots — does not change between Hermes versions. Only the patched files need updating.

---

## Summary: The Design Logic

| Decision | Why |
|----------|-----|
| Separate profile per agent | Isolated memory, state, cron DB — prevents cross-contamination |
| Same codebase for all agents | Patches apply once, all agents benefit |
| One Telegram bot per agent | Each agent owns its topic; routing by mention pattern |
| HERMES_EXEC_ASK=0 | Autonomous cron operation — no human-in-the-loop |
| skip_memory=False + messaging enabled | Team coordination via shared memory and direct message delivery |
| Concurrent cron workers (20) | Multiple agents scheduling jobs simultaneously without blocking |
| Re-apply script after every update | Patches are the only fragile part; restore them in one command |

The architecture is not a hack. It is the intentional use of Hermes's native multi-profile, multi-gateway design — stretched to its logical conclusion: a zero-human lab where every entity has its own agent, every agent has its own bot, and the whole fleet runs on cron without a single person checking in.

---

## TL;DR — Give This to an Agent

> Set up Hermes for a multi-agent fleet? Here is the checklist:
> 1. Install Hermes once at `~/.hermes/hermes-agent`
> 2. Create one profile directory per agent at `~/.hermes/profiles/<name>/`
> 3. Set up one Telegram bot per agent; each bot in its own group/topic
> 4. Configure PM2 ecosystem with `HERMES_HOME`, `TELEGRAM_BOT_TOKEN`, `HERMES_CRON_MAX_WORKERS=20`, `HERMES_EXEC_ASK=0` per agent
> 5. Run the re-apply script after every Hermes update
> 6. Stagger cron schedules so simultaneous due jobs do not pile up
> 7. Use shared brain files for inter-agent context sharing; per-profile memory for agent-local state
