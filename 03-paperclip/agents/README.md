# The company roster

`03-paperclip/create-company.sh` builds the whole org from this folder in one run,
through Paperclip's CLI. Nothing here is pasted by hand, and the CEO does not hire
anyone: every agent, its model, its instructions and its permissions are set here,
in git, so the setup is repeatable and reviewable.

| Folder | Agent | Harness / model | Costs | Gate |
|---|---|---|---|---|
| `ceo/` | CEO | Claude Code, **claude-sonnet-5-5** | your Max plan (light) | routes work; cannot code |
| `reviewer/` | Reviewer | Codex (ChatGPT Plus) | your Plus plan | reviews every PR |
| `watchdog/` | Watchdog | Pi, `devco/coder-fast` (local) | free | verifies "done" claims |
| `pyro/` | pyro | Hermes profile, `coder-accurate` (local) | free | Python / PySide6 |
| `webby/` | webby | Hermes profile, `coder-accurate` (local) | free | web / single-file HTML |
| `ops/` | ops | Hermes profile, `coder-accurate` (local) | free | Docker / homelab / CI |
| `principal-engineer/` | Principal Engineer | Claude Code, **claude-opus-5-5** | your Max plan | CEO escalates after a junior failed (ladder rules in `ceo/AGENTS.md`) |
| `chief-architect/` | Chief Architect | Claude Code, **claude-fable-5-1** | your Max plan (50 % cap) | CEO escalates after the Principal failed, or for project-shaping design; works from a brief |

Each folder has:

- `agent.json` — what `paperclipai agent create` receives (adapter, model, limits,
  permissions). Placeholders `__HOME__`, `__REPOS__`, `__GATEWAY__`, `__CEO_ID__` are
  filled by the script.
- `AGENTS.md` — the agent's instructions, uploaded as its Paperclip instruction
  bundle. The CEO also gets `HEARTBEAT.md` and `SOUL.md`, replacing Paperclip's
  revenue-and-customers defaults (which would otherwise tell it to hire people).

## How the gates actually work (verified against Paperclip's source, Oct 2026)

- **Escalation is a rule, not a gate.** The CEO may assign to the Principal and the
  Architect; its AGENTS.md ladder says when (junior failed → Principal; Principal failed
  or project-shaping design → Architect, from a brief). If you ever want a hard block
  instead, `authorizationPolicy.assignmentPolicy.mode = "protected"` on an agent makes
  Paperclip refuse any *agent* (the CEO included) that tries to assign to it; you, as the
  board, still can. An "Approver" on a task's execution policy is **not** a start gate:
  it only runs after the executor finishes.
- **Hiring.** The CEO keeps the ability to propose hires, but the company setting
  "Require board approval for new hires" is on, so a hire waits in Approvals.
- **Budgets.** Since Paperclip v2026.1023 any budget blocks *unpriced* usage by default.
  Local models have no price, so the script sets `unpricedUsagePolicy: allow` on the
  company budget. Without that, every Hermes and Pi run would stall on day one.
- **Heartbeats.** Every agent is created with the timer off and wake-on-demand on.
  Nothing runs on a schedule except the routines you create, which run on local models.
- **Pausing.** The Chief Architect is created paused. `devco pause` / `devco resume`
  (or the agent page) pause the Principal and Architect while you code interactively.

## Changing the roster later

Edit the files, then re-run `create-company.sh`. It is idempotent: existing agents
(matched by name) get their config and instructions updated; new folders create new
agents. To remove an agent, archive it in the UI (the script never deletes).

## The three Hermes juniors

They are ordinary `hermes_local` agents: Paperclip runs `hermes chat -q …` itself,
with `HERMES_HOME` pointing at the profile (`~/.hermes/profiles/<name>`), and injects
its API URL and a per-run key into the process. No Hermes gateway, no API server, no
ports, no invite flow. Their personality and skills live in the profile
(`04-hermes/profiles/<name>/`), their Paperclip-facing rules in `AGENTS.md` here.

Two details that are easy to break (both verified against Paperclip's adapter source):

- `agent.json` sets `model: coder-accurate` and **no `provider`**. Paperclip compares an
  explicit provider with the one in `~/.hermes/config.yaml` and warns on mismatch, and a
  warning fails the agent's harness check.
- `04-hermes/create-profiles.sh` writes the gateway config into the **default** Hermes
  profile too. Paperclip's harness check reads `~/.hermes/config.yaml` (not the
  profile's) to see that a model and key are configured; without it every junior is
  created paused with "No LLM API keys found".

- Hermes 0.22 runs every chat through **one long-lived gateway daemon**, and the shell
  commands an agent runs inherit the environment of the `hermes chat` that *started* the
  daemon. Paperclip passes each run its API token/run id/task id in the environment, so a
  daemon left over from a previous run (they idle out after 10 min by default) makes every
  Paperclip write return 403 and the recovery loop keeps re-waking the agent. The profile
  config therefore sets `gateway.standalone: true` and `unmanaged_idle_exit_seconds: 5`:
  one gateway per profile, gone a few seconds after each run.

The CEO is the other one that is easy to break, in the opposite direction: a capable
model dropped into a checkout with a concrete ticket will just do the work. So the CEO
runs with `--disallowedTools Edit Write NotebookEdit MultiEdit "Bash(git commit *)"
"Bash(git push *)" "Bash(gh pr create *)"` (`extraArgs` in its `agent.json`; a bare tool
name removes the tool from the model entirely, permission mode or not), its AGENTS.md
spells out the routing procedure step by step, and tasks from the board carry **no
Project** so the CEO never runs inside a repo (README Phase 5).

## The harness check

Paperclip verifies every agent it creates with a real check of its harness (CLI present,
logged in, model reachable; for Pi and managed connections a real "hello" request) and
**pauses the agent if that fails**, with the reason on the agent page. `create-company.sh`
waits for the checks and prints the failures; fix the cause, then `devco retry` (or re-run
the script). This is also why the script runs *after* the logins and after the gateway is up.
