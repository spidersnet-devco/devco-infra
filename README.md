# Spidersnet Dev Co. — build package for the MS-S1 Max ("Hermes")

> **v3** (2026-10-31): audited against the current sources of everything it installs
> (Paperclip v2026.1023, llama.cpp master, llama-swap v268, Hermes Agent, Ubuntu 26.04.1,
> Claude Code / Codex / gh docs). Unattended install now runs through Phase 3; the company
> is built by a script from `03-paperclip/agents/`; juniors run as `hermes_local` agents.
> v2 was the first repo-based version; v1 was a zip.

A one-box AI software company: Paperclip as the control plane, a Claude Code CEO on
your Max plan, Codex on your ChatGPT Plus plan, three specialist Hermes Agent juniors
and a Pi watchdog on local models, and a QA script that isn't an LLM at all.
Everything is addressed by **role**, not by machine or model, so Athena can be added
later by editing one gateway config (see `05-expansion/`).

```
                 ┌────────────────────────────────────────────────────────────────┐
                 │  MS-S1 Max  (Ryzen AI Max+ 395, 128 GB unified)                 │
                 │                                                                │
  you (board) ──▶│  Paperclip :3100 ──┬─ CEO              Claude Code  sonnet-5-5  │── Max 20x
  phone/laptop   │  (control plane)   ├─ Principal Eng    Claude Code  opus-5-5    │── Max 20x  [protected]
                 │                    ├─ Chief Architect  Claude Code  fable-5-1   │── Max 20x  [protected, paused]
                 │                    ├─ Reviewer         Codex                    │── ChatGPT Plus
                 │                    ├─ Watchdog         Pi ─────────────┐        │
                 │                    ├─ pyro             Hermes profile ─┤        │
                 │                    ├─ webby            Hermes profile ─┤        │
                 │                    ├─ ops              Hermes profile ─┤        │
                 │                    └─ QA  /opt/devco/bin/qa-run.sh (no LLM)    │
                 │                                                       ▼        │
                 │  llama-swap :8080  (model gateway, role aliases)                │
                 │     coder-accurate → gpt-oss-120b MXFP4         (63 GB)        │
                 │     coder-fast     → Qwen3.6-35B-A3B UD-Q4_K_XL (22 GB)        │
                 │                                                                │
                 │  /opt/devco/repos/<project>   git clones the agents work in     │
                 │  GitHub org spidersnet-devco  branches + PRs as the bot; you merge │
                 └────────────────────────────────────────────────────────────────┘
                        later: peers: athena → coder-fast-gpu  (05-expansion)
```

## The ladder (who gets what)

| Rung | Agent | Harness / model | Pays from | Runs |
|---|---|---|---|---|
| 1 | pyro, webby, ops | Hermes Agent → `coder-accurate` (local) | nothing | first pass on everything |
| 2 | Reviewer | Codex | ChatGPT Plus | reviews every PR; medium tasks |
| 3 | Principal Engineer | Claude Code `claude-opus-5-5` | Max 20x | hard tasks; a junior failed; **only you can assign to it** |
| 4 | Chief Architect | Claude Code `claude-fable-5-1` | Max 20x (50 % cap, burns faster) | Principal failed, or project-shaping design; **only you can assign**; works from a brief; starts paused |
| — | CEO | Claude Code `claude-sonnet-5-5` | Max 20x | writes tickets, routes, reports; never codes; no timer |
| — | Watchdog | Pi → `coder-fast` (local) | nothing | verifies "done" claims |
| — | QA | `/opt/devco/bin/qa-run.sh` | nothing | lint + tests, every hand-back, nightly |

"Protected" is a real Paperclip gate: no agent, the CEO included, can hand those two
work. The CEO writes a brief and asks you in your Inbox; you assign.

## Prerequisites

- The MS-S1 Max with its stock 2 TB NVMe, wired to the LAN. **Ubuntu Server 26.04.1 LTS**
  (kernel 7.0). Not 24.04: its kernel has no driver for this box's RTL8127 10 GbE ports.
- Accounts: Claude Max (Claude Code login), ChatGPT Plus (Codex login). No API keys;
  both use your plans. The local models need nothing.
- GitHub: the org `spidersnet-devco` with your projects in it, plus the bot account
  (`03-paperclip/agents/github-access.md`). Agents push branches and open PRs as the
  bot; you merge. Nothing of your own account ever goes on the box.
- ~90 GB of NVMe for models, plus whatever your repos need.

## Fastest path: the unattended install

`00-unattended/` turns the OS install, Phase 0, the reboot, Phase 1 and the no-login
parts of Phases 2 and 3 into "boot a stock Ubuntu USB, type one line at the boot menu,
come back in an hour." The installer pulls its answers from this repo on GitHub (which
is why the repo is public), and the box boots into a running model gateway, Paperclip
as a service, Hermes with its three profiles, and the bot's SSH key generated. Read
`00-unattended/README.md`; then come back here and start at **Phase 2**.

| Layer | What it removes | Status |
|---|---|---|
| Ubuntu autoinstall pulled from GitHub (`00-unattended/user-data`) | installer screens, the answers USB, the small-root-partition mistake, user/ssh/network setup | done |
| First-boot bootstrap (`devco-bootstrap.service`) | Phase 0, the kernel-param reboot, Phase 1 (build, 86 GB download, gateway), Paperclip + Hermes installs | done |
| `03-paperclip/logins.sh` | hunting for the five login commands; batches them as device codes you do from your phone | done |
| `03-paperclip/create-company.sh` | clicking the CEO's model, instructions, every hire, budgets and routines into the UI | done |
| Claude Code on the box | fixing what breaks on this specific hardware, with `CLAUDE.md` as its rules | done |
| Paperclip company **export** | a rebuild without re-running `create-company.sh`: Company → Export, scrub LAN IPs, commit as `03-paperclip/company-export/` | after the first full setup |

What never gets automated: the logins, creating the GitHub bot account, assigning
work to the Opus/Fable agents, approving hires, and merging PRs. Those are the points
where a human is the feature.

## How to run this runbook: let Claude Code drive

This repo is meant to be executed by Claude Code **on the box**, with you supervising
over SSH. `CLAUDE.md` tells it the rules (one phase at a time, fix scripts in the repo,
stop before reboots and logins). The unattended install leaves Claude Code installed;
sign it in and open the repo:

```bash
ssh geoff@hermes.local
claude auth login                    # your Max plan
cd ~/devco-infra && claude
```

Then, phase by phase:

```
Read README.md and CLAUDE.md, run `devco status`, and tell me where the box is. Then execute Phase 2 only.
```

It reads the scripts, runs them, fixes what breaks on this specific box, commits the
fixes, and tells you when to log in to something.

**Installed Ubuntu by hand instead?** Make the root volume use the whole disk in the
installer's storage screen (the default stops at 100 GB), then after the first login:

```bash
git clone https://github.com/spidersnet-devco/devco-infra.git ~/devco-infra   # repo must be public, or use a token
sudo bash ~/devco-infra/00-unattended/bootstrap-manual-install.sh            # same first-boot automation; reboots once
tail -f /opt/devco/bootstrap.log
```

That gives a hand-installed box the same Phases 0–3 automation, ending at the same
place: continue at Phase 2 below. (Claude Code, if you want it before that, comes from
`curl -fsSL https://claude.ai/install.sh | bash`, never `sudo npm`.)

If you'd rather type the commands yourself, every phase below is still a plain
`bash <script>` you can run by hand.

## Phase 0 — base + kernel parameters (15 min + a reboot)

*Done by the unattended install.* By hand:

```bash
cd ~/devco-infra
bash 01-base/install-base.sh               # packages, Node 24, Claude Code, hf, Playwright, dirs, swap
nano /opt/devco/devco.env                  # DEVCO_LAN_IP, GIT_MIRROR_DIR at minimum
bash 01-base/apply-kernel-params.sh && sudo reboot
```

What the kernel parameters do and why: `01-base/strix-halo-kernel.md`. Verify
`mem_info_gtt_total` is ≥ 120 GB before going further; nothing below works otherwise.

## Phase 1 — models (1–2 h, mostly download)

*Done by the unattended install.* By hand:

```bash
bash 02-models/install-llamacpp.sh         # Vulkan build pinned to a release tag; or --container
bash 02-models/download-models.sh          # ~86 GB (gpt-oss-120b + Qwen3.6-35B-A3B)
bash 02-models/install-llama-swap.sh       # gateway on 127.0.0.1:8080, both models resident, tool-call smoke test
```

Check `http://127.0.0.1:8080/ui` (ssh tunnel: `ssh -L 8080:127.0.0.1:8080 <box>`).
Both `coder-accurate` and `coder-fast` show `ready`, and the install script's smoke
test printed `tool call OK` for both.

## Phase 2 — Paperclip, logins, the company (40 min, half of it on your phone)

```bash
bash 03-paperclip/install-paperclip.sh     # done by the unattended install; safe to re-run
bash 03-paperclip/logins.sh                # 1 Claude  2 Codex  3 gh as the bot  4 Paperclip claim  5 Paperclip CLI
```

Before step 3 of the logins you need the bot account and its no-reply address
(`03-paperclip/agents/github-access.md`, 10 minutes in a browser as you). Then:

```bash
bash 03-paperclip/create-company.sh        # CEO on Sonnet, instructions, goal, 7 agents, budget, routines
devco status
```

That script is the company. Everything it sets lives in `03-paperclip/agents/`; to
change an agent, edit there and re-run. Notes on what it does and why are in
`03-paperclip/agents/README.md`. Two things to know up front:

- Paperclip's wizard may create a CEO for you when you claim the instance. The script
  finds it (by role) and fixes its model: left alone, **Paperclip runs a Claude CEO on
  Opus**, which would eat your Max plan on day one.
- The CEO's first run can sit in **Approvals** as "CEO Strategy". Approve it once.

Why Sonnet for the CEO: it wakes every time a subtask reports back. Sonnet draws far
less of your weekly limit per wake than Opus, and writing tickets for your own
projects doesn't need Opus. Flip it later if the plans are weak.

## Phase 3 — Hermes juniors (10 min; the installs are done unattended)

```bash
bash 04-hermes/install-hermes.sh           # done by the unattended install
bash 04-hermes/create-profiles.sh --smoke  # pyro, webby, ops: SOUL, skills from this repo, gateway config; one test question each
```

There is no invite, no gateway, no port per profile any more. Paperclip runs each
profile itself (`hermes_local` adapter, `HERMES_HOME=~/.hermes/profiles/<name>`) and
hands it the API URL and a per-run key in the environment. `create-company.sh` already
created the three agents; this phase only makes sure the profiles answer.

## Phase 4 — the first project (10 min)

```bash
/opt/devco/bin/clone-project.sh peel --python --bootstrap-pr
```

Clones the repo into `/opt/devco/repos/peel` as the bot, builds its venv, creates the
two review labels, runs a baseline QA pass, registers it in Paperclip as a Project with
that folder as its codebase (shared workspace, runs serialized), and opens a PR adding
`AGENTS.md` + `.gitignore` for you to merge. From here on every engineer hands back a
**pull request**, the Reviewer comments and labels it on GitHub, and you merge it there
(phone is fine).

Recommended at this point: the nightly mirror and backup to the NAS,
`devco mirror-timer` and `devco backup --install-timer` (both need the share mounted;
`GIT_MIRROR_DIR` in `devco.env`).

## Phase 5 — the first ticket

Something small, verifiable, and in one junior's field. Create it in Paperclip as a
task assigned to the **CEO** with **no Project** — a Project would drop the CEO into
that repo's checkout, and the CEO's job is to route, not to code. Name the project in
the first line instead; the CEO sets the Project field on the ticket it creates for
the engineer. For Peel, a good first one:

```
Project: peel. Add a pytest smoke test for Peel.
Context: the code is flat modules in src/ (no package, no pyproject), so nothing imports
until src/ is on sys.path. The GUI is PySide6; the main window is peel_gui.MainWindow;
constructing it must not load or download any rembg model.
Do: (1) add pytest.ini at the repo root with [pytest] testpaths = tests and
pythonpath = src; (2) add tests/test_smoke.py that imports peel_core and peel, then with
QT_QPA_PLATFORM=offscreen creates a QApplication (reuse QApplication.instance() if one
exists), constructs peel_gui.MainWindow() and closes it without error; (3) run qa-run.sh
and make it pass.
Done means: the test is collected and passes under qa-run.sh, nothing else in the repo
changes. Branch: devco/<ticket-id>-pytest-smoke.
```

Watch the whole loop: CEO routes it (a child ticket on pyro, Project peel, Reviewer
and Watchdog attached; the CEO's own task goes `blocked` on it) → pyro → QA → PR on
GitHub → Reviewer (comment + `reviewer-approved` label) → Watchdog → CEO report → you
merge → you close the ticket.
Fix whatever breaks in the wiring before giving it anything real.

## Phase 6 — lock down (5 min)

```bash
passwd                                      # replace the throwaway console password
/opt/devco/bin/lockdown.sh
```

Until this runs, your user has passwordless sudo and **every agent runs as that user**:
any agent command could become root with no prompt. Lockdown removes that, makes the
gateway config and the company scripts root-owned, and installs a git hook that refuses
pushes to `main`. `sudo devco unlock` undoes it for maintenance.

## Protecting your Max plan (the whole point)

- CEO on `claude-sonnet-5-5`; Principal (Opus) and Architect (Fable) are **protected**
  (only you can assign) and never on timer heartbeats. The Architect starts paused.
- **`devco pause` before you code interactively**, `devco resume` after. The two
  Claude-backed engineers draw from the same 5-hour window you do. Let them run overnight.
- Turn on **usage credits with a monthly cap** on your Claude account (Settings → Usage;
  formerly "Extra Usage") so a 5-hour limit never hard-stops you mid-flow. Headless
  agents consume credits without asking, so the cap is the real guard.
- Fable: 50 % of your weekly limit and it burns faster. Four rungs exist so it fires a
  few times a week at most. It never reads a repo cold; it gets a brief.
- Paperclip's budgets cap *billed* spend; they do **not** protect subscription plans.
  Company → **Costs** in the UI shows the Claude 5-hour/7-day windows and the ChatGPT
  window for the host logins; that's where you'll see Plus run dry.
- The three Hermes juniors and the Watchdog cost nothing. Let them churn.

## Memory budget (128 GB unified, decimal GB)

| Consumer | ~GB |
|---|---|
| gpt-oss-120b weights (MXFP4) | 63 |
| its KV cache, 3 slots × 64K, q8_0, + compute buffers at `-ub 2048` | 6–7 |
| Qwen3.6-35B-A3B weights (UD-Q4_K_XL) | 22 |
| its KV + recurrent state, 4 slots × 64K, + compute | 3–4 |
| llama-server prompt caches (`--cache-ram 2048` × 2) | 4 |
| OS, Paperclip + embedded Postgres, Hermes runs, CLIs, builds | 15–25 |
| **Headroom** | **~5–15** (+ a 16 GB swapfile as OOM insurance) |

If that's tight: set `swap: true` in the `local` group in llama-swap.yaml so only one
model is resident, or drop `coder-fast` to `--parallel 2`.

## Day to day

- `http://<ip>:3100` on your phone is the company. Inbox = things waiting on you
  (questions, escalation requests, join requests, approvals).
- `devco status` on the box: gateway, Paperclip agents and their models, Hermes
  profiles, logins, mirror, lockdown state. `devco logs gateway|paperclip|bootstrap`.
- Weekly: read the skills-review task; delete bad skills in
  `~/.hermes/profiles/<name>/skills/`. The juniors learn from successes and will
  happily learn the wrong lesson.
- Nightly, automatic: QA sweep (Watchdog), repo mirror and state backup to the NAS.
- Every change to this box's config goes through this repo. Once the company runs, that
  means a ticket to `ops`, a PR, and a merge, same as any project. The gateway config is
  the exception: root-owned after lockdown, you change it yourself.
- Model swap: new GGUF → `download-models.sh` → `llama-swap.yaml` macro →
  `llama-swap -validate` → `systemctl --user restart llama-swap`. Nothing else changes.
  Candidates and the reasoning are in the comments of `02-models/llama-swap.yaml`.

## Adding Athena later

`05-expansion/athena-fast-lane.md`. Summary: Athena serves `coder-fast-gpu` on its own
llama-swap (CUDA); the Hermes box's gateway gets a `peers:` entry and a **profile** that
pins `coder-fast` to Athena; `wake-athena.sh` switches the profile on when Athena
answers, `sleep-athena.sh` switches it off. Agents don't change.

## Troubleshooting

| Symptom | Fix |
|---|---|
| gpt-oss-120b fails to load / "failed to allocate" | Kernel params not applied. `mem_info_gtt_total` must be ≥ 120 GB; `cat /proc/cmdline` must show `ttm.pages_limit`. |
| llama-server exits with "invalid argument" | A flag was removed upstream. The `llama` macro in `llama-swap.yaml` is verified for Oct 2026; `--no-mmap` is gone (`--load-mode none`), `-fa` needs a value. |
| Vulkan doesn't list the 8060S | Mesa too old (not on 26.04), or your user isn't in `video`/`render` yet (re-login). Or `install-llamacpp.sh --container`. |
| Tool calls come back as text JSON | A client not sending `tools`, or a template/parser mismatch; `--jinja` is on by default. Check the smoke test in `install-llama-swap.sh`. |
| Hermes refuses to start: context < 64K | Gateway slot too small. `--ctx-size` ÷ `--parallel` must be ≥ 65536. |
| Agent created **paused** with "The lifecycle step failed" | Paperclip's harness check failed: CLI missing or not logged in, gateway down, or (Hermes) the default profile has no gateway config. Fix, then `devco retry`. |
| Hermes junior runs but never reports | Its Paperclip agent must be `hermes_local` with `env.HERMES_HOME` set (`create-company.sh` does this); check the run log in Paperclip for `[hermes] Starting`. |
| CEO run fails: CLI too old for the model | `claude_cli_version_incompatible`: `claude update` (Fable 5.1 needs ≥ 2.1.257). |
| CEO: "ACP agent reported a terminal access failure" | `claude` not signed in on this box. `claude auth login`, then Inbox → Retry. |
| Local-model runs stall with a budget hold | A budget policy without `unpricedUsagePolicy: allow`. `create-company.sh` sets it; re-run, or Company → Costs → Budgets. |
| Agent fails with a sandbox/low-trust error | Agent → Permissions / Trust → preset Standard. |
| Browser: hostname not allowed | `paperclipai allowed-hostname <ip> && paperclipai service restart`. |
| Codex agent won't run | `codex login --device-auth` on this box, not your laptop; Plus quota may be exhausted (Company → Costs). |
| `gh pr create` fails with 403 / "not permitted" | The bot lacks Write on that repo: repo Settings → Collaborators and teams → `agents` → Write. |
| `gh pr edit --add-label` fails | Labels missing on that repo: re-run `clone-project.sh <repo>` with gh logged in. |
| `ssh -T git@github.com` says "Permission denied (publickey)" | The bot's public key wasn't added to the bot account, or `~/.ssh/config` isn't pointing at `id_ed25519_devco_bot`. Re-run `github-setup.sh`. |
| Commits show up under the wrong name | `git config --global --list` on the box should show the bot's name and no-reply email; `GITHUB_BOT_NOREPLY` must be set in `devco.env`. |
| Everything slow at once | Too many concurrent local requests. 3 accurate + 4 fast slots is the box's limit; Paperclip queues the rest. |

## File map

```
CLAUDE.md                 rules for Claude Code when it runs this repo on the box
SECRETS.md                what is secret, where it lives, what must never be in this repo
NOTES.md                  what deviated on this box, versions installed (NOTES.local.md for IPs/ids, gitignored)
docs/first-week.md        what to expect and check in the first week of running the company
devco.env.example         one place for machine-specific values (real copy is never committed)
bin/devco                 the day-to-day command: status, pause/resume, qa, costs, logs, backup
bin/backup-devco.sh       Paperclip DB + Hermes profiles + /opt/devco to the NAS
00-unattended/            user-data, meta-data, devco-bootstrap.sh/.service, bootstrap-manual-install.sh, README.md
01-base/                  install-base.sh, apply-kernel-params.sh, strix-halo-kernel.md
02-models/                install-llamacpp.sh, download-models.sh, llama-swap.yaml, llama-swap.service, install-llama-swap.sh
03-paperclip/             install-paperclip.sh, logins.sh, github-setup.sh, create-company.sh, clone-project.sh, lockdown.sh, pi-models.json
             agents/      README.md (the roster), company-mission.md, github-access.md,
                          ceo/ reviewer/ watchdog/ pyro/ webby/ ops/ principal-engineer/ chief-architect/  (agent.json + AGENTS.md)
             routines/    qa-run.sh, nightly-qa.md, standup.md, skills-review.md, mirror-repos.sh, mirror-repos.timer.md
             templates/   gitignore-{python,web,stacks}, AGENTS.md.template
             tools/       smoke.py (headless browser smoke test)
04-hermes/                install-hermes.sh, create-profiles.sh, config.template.yaml,
                          profiles/shared-skills/devco-workflow, profiles/{pyro,webby,ops}/{SOUL.md,skills/*}
05-expansion/             athena-fast-lane.md, wake-athena.sh, sleep-athena.sh
tests/                    run-tests.sh: syntax, YAML/JSON, autoinstall placeholders, qa-run.sh fixtures
```
