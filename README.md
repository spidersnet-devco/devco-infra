# Spidersnet Dev Co. — build package for the MS-S1 Max ("Hermes")

> **v2** (2026-10-31): repo-based install driven by Claude Code on the box, GitHub org
> + bot account, PR-based hand-backs, nightly NAS mirror. v1 was a zip.

A one-box AI software company: Paperclip as the control plane, a Claude Code CEO on
your Max plan, Codex on your ChatGPT Plus plan, three specialist Hermes Agent juniors
and a Pi watchdog on local models, and a QA script that isn't an LLM at all.
Everything is addressed by **role**, not by machine or model, so Athena can be added
later by editing one gateway config (see `05-expansion/`).

```
                 ┌──────────────────────────────────────────────────────────┐
                 │  MS-S1 Max  (Ryzen AI Max+ 395, 128 GB unified)           │
                 │                                                          │
  you (board) ──▶│  Paperclip :3100 ──┬─ CEO            Claude Code (sonnet)  │── Max 20x
  phone/laptop   │  (control plane)   ├─ Principal Eng  Claude Code (opus)    │── Max 20x  [gated]
                 │                    ├─ Chief Architect Claude Code (fable)  │── Max 20x  [gated]
                 │                    ├─ Reviewer       Codex                 │── ChatGPT Plus
                 │                    ├─ Watchdog       Pi ──────────┐        │
                 │                    ├─ pyro   Hermes :8642 ───┐    │        │
                 │                    ├─ webby  Hermes :8643 ───┤    │        │
                 │                    ├─ ops    Hermes :8644 ───┤    │        │
                 │                    └─ QA     /opt/devco/qa-run.sh (no LLM) │
                 │                                             ▼    ▼        │
                 │  llama-swap :8080  (model gateway, role aliases)           │
                 │     coder-accurate → gpt-oss-120b MXFP4   (~61 GB)        │
                 │     coder-fast     → Qwen3-Coder-30B-A3B  (~18 GB)        │
                 │                                                          │
                 │  /opt/devco/repos/<project>  (git clones agents work in)  │
                 └──────────────────────────────────────────────────────────┘
                        later: peers: athena → coder-fast-gpu  (05-expansion)
```

## The ladder (who gets what)

| Rung | Agent | Harness / model | Pays from | Runs |
|---|---|---|---|---|
| 1 | pyro, webby, ops | Hermes Agent → `coder-accurate` (local) | nothing | first pass on everything |
| 2 | Reviewer | Codex | ChatGPT Plus | reviews every PR; medium tasks |
| 3 | Principal Engineer | Claude Code `opus` | Max 20x | hard tasks; a junior failed once; **board approval per task** |
| 4 | Chief Architect | Claude Code `fable` | Max 20x (50% cap, burns faster) | Principal failed, or project-shaping design; **board approval per task**; works from a brief |
| — | CEO | Claude Code `sonnet` | Max 20x | plans, routes, reviews reports; never codes; no timer heartbeats |
| — | Watchdog | Pi → `coder-fast` (local) | nothing | verifies "done" claims |
| — | QA | `/opt/devco/qa-run.sh` | nothing | lint + tests, every hand-back |

## Prerequisites

- MS-S1 Max running **Linux**: Ubuntu 25.10 Server or Fedora 43 Server (kernel 6.14+,
  Mesa 25+). Avoid Ubuntu 24.04 LTS on this chip. At install time, make root use the
  **whole 2 TB** (the installer defaults to a small root volume). Everything runs as your
  normal user with systemd user services and linger enabled.
- Accounts: Claude Max (Claude Code login), ChatGPT Plus (Codex login). No API keys
  needed; both use your plans. The local models need nothing.
- GitHub: the org `spidersnet-devco` with your projects in it, plus the bot account
  (`03-paperclip/agents/github-access.md`). Agents push branches and open PRs as the
  bot; you merge.
- ~90 GB of NVMe for models, plus whatever your repos need.

## Fastest path: the unattended install

`00-unattended/` turns the OS install, Phase 0, the reboot, and Phase 1 into "plug in
two USB sticks, type `yes` once, come back in an hour." The box boots into a running
model gateway with no typing on it at all. Read `00-unattended/README.md`; if you use
it, skip to **Phase 2** below.

The ladder of automation, for reference:

| Layer | What it removes | Status |
|---|---|---|
| Ubuntu autoinstall (`00-unattended/autoinstall.yaml`) | the installer screens, the small-root-partition mistake, user/ssh setup | done |
| First-boot bootstrap (`devco-bootstrap.service`) | Phase 0, the kernel-param reboot, Phase 1 (build, 80 GB download, gateway) | done |
| `03-paperclip/logins.sh` | hunting for the four login commands; batches them as device codes you do from your phone | done |
| Claude Code on the box driving Phases 2–5 | typing the remaining scripts, fixing what breaks | done (`CLAUDE.md`) |
| Paperclip company **export/import** | re-clicking the mission, settings, agents, routines on a rebuild | after the first full setup: Board → Settings → Export, commit the package here as `03-paperclip/company-export/` |
| Hermes profile **distributions** | re-seeding SOUL/skills on another machine | after the juniors have learned something worth keeping: `hermes profile export <name>` |

What never gets automated: the four logins (Claude, Codex, gh as the bot, Paperclip
claim), creating the GitHub bot account, approving hires, and merging PRs. Those are
the points where a human is the feature.

## How to run this runbook: let Claude Code drive

This repo is meant to be executed by Claude Code **on the box**, with you supervising
over SSH. `CLAUDE.md` tells it the rules (one phase at a time, fix scripts in the repo,
stop before reboots and logins). So the very first thing on a fresh install is Claude
Code itself:

```bash
# fresh box, over ssh
sudo apt-get update && sudo apt-get install -y git curl
curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/n.sh && sudo -E bash /tmp/n.sh
sudo apt-get install -y nodejs
sudo npm install -g @anthropic-ai/claude-code
claude                                      # sign in with your Max plan, then /exit

git clone https://github.com/spidersnet-devco/devco-infra.git ~/devco-infra
cd ~/devco-infra && claude
```

Then, phase by phase:

```
Read README.md and CLAUDE.md. Execute Phase 0 only. Stop before the reboot.
```

It reads the scripts, runs them, fixes what breaks on this specific box, commits the
fixes, and tells you when to reboot or log in to something. After the reboot, open
`claude` again in `~/devco-infra` and say `Phase 1`. The clone is over HTTPS and
read-only until Phase 2's `github-setup.sh` signs the box in as the bot; until then
Claude Code's own `claude` login is enough to *read* the repo, and it can push its
fixes once the bot has Write on `devco-infra` (give the `agents` team Write on it too).

If you'd rather type the commands yourself, every phase below is still a plain
`bash <script>` you can run by hand.

## Phase 0 — prep (15 min + a reboot)

```bash
cd ~/devco-infra
bash 01-base/install-base.sh
nano /opt/devco/devco.env                  # DEVCO_LAN_IP, GIT_MIRROR_DIR at minimum
```

Then `bash 01-base/apply-kernel-params.sh && sudo reboot` (what it does and why:
`01-base/strix-halo-kernel.md`). Verify `mem_info_gtt_total` shows ~128 GB before going
further; nothing below works otherwise.

## Phase 1 — models (1–2 h, mostly download)

```bash
bash 02-models/install-llamacpp.sh         # Vulkan build; or --container
bash 02-models/download-models.sh          # ~80 GB
bash 02-models/install-llama-swap.sh       # gateway on 127.0.0.1:8080, both models resident
```

Check `http://127.0.0.1:8080/ui` (ssh tunnel: `ssh -L 8080:127.0.0.1:8080 <box>`).
Both `coder-accurate` and `coder-fast` should show as running.

## Phase 2 — Paperclip + the harness CLIs (30 min)

```bash
bash 03-paperclip/install-paperclip.sh
```

Then the logins, all four from your phone in one sitting:

```bash
bash 03-paperclip/github-setup.sh          # creates the bot's SSH key first
bash 03-paperclip/logins.sh                # Claude, Codex, gh-as-bot, Paperclip claim
```

Then the UI steps: set the mission (`agents/company-mission.md`), turn on hire
approval, paste `agents/ceo-AGENTS.md` into the CEO's AGENTS.md, set the CEO's model
to `sonnet`.

Why Sonnet for the CEO: it wakes every time a subtask reports back. Sonnet draws far
less of your weekly limit per wake than Opus, and planning tickets for your own
projects doesn't need Opus. Flip it later if the plans are weak.

## Phase 2b — GitHub as the bot (20 min, half of it in a browser)

Browser, as you: create the bot account, invite it to the org, make the `agents` team,
give the team Write on each project repo. Exact clicks in
`03-paperclip/agents/github-access.md`. Then on the box:

```bash
bash 03-paperclip/github-setup.sh          # bot SSH key + gh login + git identity
/opt/devco/bin/clone-project.sh peel --python
```

`clone-project.sh` pulls the repo into `/opt/devco/repos/peel`, adds an `AGENTS.md`
stub if there isn't one, runs a baseline QA pass, and prints what to enter when you
register it as a Project in Paperclip. From here on every engineer hands back a
**pull request**, the Reviewer reviews it on GitHub, and you merge it there (phone
is fine).

Optional but recommended: the nightly mirror of every org repo to the NAS,
`03-paperclip/routines/mirror-repos.timer.md`.

## Phase 3 — Hermes juniors (30 min)

```bash
bash 04-hermes/install-hermes.sh
bash 04-hermes/create-profiles.sh          # pyro, webby, ops: SOUL, skills, gateway, API server
```

Then `03-paperclip/agents/hire-tickets/invite-hermes-juniors.md` for each profile
(invite → paste into `pyro chat` → approve → write the four `PAPERCLIP_*` lines into
that profile's `.env` → `hermes -p pyro gateway restart`). The step people miss is the
last one; without it the agent works and reports to nobody.

## Phase 4 — hire the rest (20 min)

Paste each of `03-paperclip/agents/hire-tickets/{reviewer,watchdog,principal-engineer}.md`
as a task assigned to the CEO; approve under Approvals. Add `chief-architect.md` when
you hit the first real wall; there's no reason to have it before then. After each
hire, check Permissions / Trust → preset Standard (the hiring skill sometimes picks a
sandboxed preset that fails on first run).

## Phase 5 — routines (10 min)

`03-paperclip/routines/routines.md`: nightly QA sweep (Watchdog), daily standup
(ops), weekly skills review (ops). All on local models; none wake a Claude agent.

## Phase 6 — the first ticket

Something small, verifiable, and in one junior's field. For Peel, a good first one:

```
Project: peel (/opt/devco/repos/peel). Branch: devco/T1-pytest-smoke.
Add a pytest smoke test that imports the package and instantiates the main window
offscreen (QT_QPA_PLATFORM=offscreen) without error. Done means: the new test exists
under tests/, qa-run.sh passes, nothing else in the repo changes.
```

Assign it to the CEO and watch the whole loop: CEO → pyro → QA → PR on GitHub →
Reviewer → Watchdog → CEO report → you merge. Fix whatever breaks in the wiring before
giving it anything real.

## Protecting your Max plan (the whole point)

- CEO on `sonnet`; Principal (`opus`) and Architect (`fable`) are **approval-gated per
  task** and never on timer heartbeats. The CEO's instructions enforce this.
- **Pause the three Claude Code agents while you code interactively** (Agents → agent →
  Pause). They draw from the same 5-hour window you do. Let them run overnight.
- Turn on **Extra Usage with a monthly cap** on your Claude account so a 5-hour limit
  never hard-stops you mid-flow; you pay API rates only for the overflow.
- Fable: 50% of your weekly limit and it burns faster. Four rungs exist so it fires a
  few times a week at most. It never reads a repo cold; it gets a brief.
- Paperclip's budgets cap *billed* spend. They do **not** protect subscription plans.
  Watch Audit → Costs for the quota windows; that's where you'll see Plus run dry.
- The three Hermes juniors and the Watchdog cost nothing. Let them churn.

## Memory budget (128 GB unified)

| Consumer | ~GB |
|---|---|
| gpt-oss-120b weights (MXFP4) | 61 |
| its KV cache, 3 slots × 64K, q8_0 | 4 |
| Qwen3-Coder-30B-A3B weights (Q4_K_M) | 18 |
| its KV cache, 2 slots × 64K, q8_0 | 6 |
| OS, Paperclip + embedded Postgres, 3 Hermes gateways, CLIs, builds | 20–30 |
| **Headroom** | **~10–20** |

If that's tight: set `swap: true` in the `local` group in llama-swap.yaml so only one
model is resident, or drop `coder-fast` to `-c 65536 --parallel 1`.

## Day to day

- `http://<ip>:3100` on your phone is the company. Inbox = things waiting on you.
- `hermes -p pyro logs -f` / `systemctl --user status llama-swap` / `paperclipai service logs --follow`.
- Weekly: read the skills-review standup; delete bad skills in
  `~/.hermes/profiles/<name>/skills/`. The juniors learn from successes and will
  happily learn the wrong lesson.
- Monthly: `hermes profile export <name>` (or `hermes backup`) to the NAS. Months of
  accumulated skills are the one thing here you can't rebuild quickly. Keeping each
  profile's skills in a private repo in the org is the better version of the same idea.
- Every change to this box's config goes through this repo. Once the company runs, that
  means a ticket to `ops`, a PR, and a merge, same as any project.
- Model swap: new GGUF → `download-models.sh` pattern → `llama-swap.yaml` macro →
  `systemctl --user restart llama-swap`. Nothing else changes.

## Adding Athena later

`05-expansion/athena-fast-lane.md`. Summary: Athena serves `coder-fast-gpu` on its own
llama-swap (CUDA); the Hermes box's gateway gets a `peers:` entry and a `coder-fast`
selector that prefers Athena when it's awake; `wake-athena.sh`/`sleep-athena.sh` run
from `ops` routines based on backlog. Agents don't change.

## Troubleshooting

| Symptom | Fix |
|---|---|
| gpt-oss-120b fails to load / "failed to allocate" | Kernel params not applied. `cat /sys/class/drm/card*/device/mem_info_gtt_total` must be ~128 GB. |
| Vulkan doesn't list the 8060S | Mesa too old. Newer distro, or `install-llamacpp.sh --container`. |
| Tool calls come back as text JSON | `--jinja` missing from the llama-server cmd (it's in the `llama` macro; check the config). |
| Hermes refuses to start: context < 64K | Gateway slot too small. `--ctx-size` ÷ `--parallel` must be ≥ 65536. |
| Hermes junior works but never reports | The four `PAPERCLIP_*` lines missing from that profile's `.env`, or gateway not restarted. |
| CEO: "ACP agent reported a terminal access failure" | `claude` not installed/signed in on this box. Install, `claude`, then Inbox → Retry. |
| New hire fails with a sandbox error | Agent → Permissions / Trust → preset Standard. |
| Browser: hostname not allowed | `paperclipai allowed-hostname <ip> && paperclipai service restart`. |
| Codex agent won't run | `codex login` on this box, not your laptop; Plus quota may be exhausted (Audit → Costs). |
| `gh pr create` fails with 403 / "not permitted" | The bot lacks Write on that repo: repo Settings → Collaborators and teams → `agents` → Write. |
| `ssh -T git@github.com` says "Permission denied (publickey)" | The bot's public key wasn't added to the bot account, or `~/.ssh/config` isn't pointing at `id_ed25519_devco_bot`. Re-run `github-setup.sh`. |
| Commits show up under the wrong name | `git config --global --list` on the box should show the bot's name and no-reply email; `GITHUB_BOT_NOREPLY` must be set in `devco.env`. |
| Everything slow at once | Too many concurrent local requests. 3 accurate + 2 fast slots is the box's limit; Paperclip queues the rest. |

## File map

```
CLAUDE.md                         rules for Claude Code when it runs this repo on the box
devco.env.example                 one place for machine-specific values (real copy is never committed)
00-unattended/ autoinstall.yaml, devco-bootstrap.sh, devco-bootstrap.service, README.md
01-base/     install-base.sh, apply-kernel-params.sh, strix-halo-kernel.md
02-models/   install-llamacpp.sh, download-models.sh, llama-swap.yaml, llama-swap.service, install-llama-swap.sh
03-paperclip/ install-paperclip.sh, github-setup.sh, logins.sh, clone-project.sh, pi-models.json,
             agents/company-mission.md, agents/ceo-AGENTS.md, agents/github-access.md,
             agents/hire-tickets/*.md,
             routines/qa-run.sh, routines/routines.md, routines/mirror-repos.sh, routines/mirror-repos.timer.md,
             templates/gitignore-{python,web,stacks}
04-hermes/   install-hermes.sh, create-profiles.sh, config.template.yaml,
             profiles/shared-skills/devco-workflow, profiles/{pyro,webby,ops}/{SOUL.md,skills/*}
05-expansion/ athena-fast-lane.md, wake-athena.sh, sleep-athena.sh
```
