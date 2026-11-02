# NOTES — what actually happened on this box

Claude Code (or you) keeps this current while running the runbook. Facts that are
box-specific and not for a public repo (LAN IPs, Paperclip ids, MACs) go in
`NOTES.local.md`, which is gitignored.

## Versions installed

Paste `devco versions` here after each phase, with the date.

```
2026-10-31 (first install; confirm with `devco versions`)
  Ubuntu Server 26.04.1 LTS, kernel 7.0.0-42
  llama.cpp 0.8.0-dev build 12024, Vulkan (RADV, "Radeon 8060S Graphics (RADV STRIX_HALO)")
  models: gpt-oss-120b-MXFP4.gguf (coder-accurate), Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf (coder-fast)
  Paperclip 2026.1023.0 (user service paperclipai.service)
  Claude Code 2.1.316, codex-cli 0.166.0, pi 1.4.0, Hermes Agent v0.22.5, gh 2.103.3
```

## Deviations from the runbook

- 2026-10-31 — Ubuntu was installed by hand (installer ISO on the JetKVM's virtual media,
  no autoinstall), so `00-unattended/bootstrap-manual-install.sh` ran the same stages
  afterwards instead of cloud-init. Same end state.
- 2026-10-31 — the hosted Paperclip installer (`paperclip.ing/install.sh`) passed
  `--no-prompt` to CLI 2026.1023.0, which only knows `--yes`; stage 2 of the first bootstrap
  failed there. `install-paperclip.sh` now runs `npx paperclipai@latest install --yes`
  itself; stage 2 was finished by re-running the script by hand.
- 2026-10-31 — Paperclip's user service runs with systemd's minimal PATH, so the CEO,
  Reviewer, Principal and Architect failed their first harness check (no `claude`/`codex`).
  Fixed in the repo: a PATH drop-in for the service plus absolute `command` paths in the
  agent definitions; `create-company.sh` retries agents that failed verification.
- 2026-10-31 — the box came up on UTC, so the three routines were first created in
  `Etc/UTC`. `timedatectl set-timezone` + re-running `create-company.sh` moved them
  (the script now re-times existing routines whenever the box's zone changes).
- 2026-10-31 — `hermes doctor` is never fully "clean" here: it always lists the
  `.env` API-key hint (the gateway is keyless and configured in config.yaml) and Hermes's
  own upstream npm-audit items. `create-profiles.sh` filters those out and reports
  anything else. `hermes chat` also auto-starts one host gateway daemon per box that
  serves every profile and exits when idle — that is Hermes 0.22 behaviour, not ours.
- 2026-10-31 — first ticket (SPI-1, Project peel, assigned to the CEO): the CEO did the
  work itself in the peel checkout in one minute — test written, nothing committed, no
  PR, no engineer, no Reviewer, no Watchdog. Paperclip's own skill tells every agent to
  "start concrete work in the same heartbeat", and a Project on the task put Sonnet in
  the repo with a numbered ticket. Fixed three ways: the CEO's harness now has no editor
  and no commit/push/PR commands (`extraArgs --disallowedTools`), its AGENTS.md has an
  explicit routing procedure (child ticket + blocker), and board tasks to the CEO carry
  no Project (README Phase 5). The stray files/branch were removed from the checkout and
  SPI-1 was cancelled; the loop was re-run as a fresh task.
- 2026-10-31 — the board's own SSH key is not on the box yet (no key on the GitHub
  account at install time); SSH is password-only until one is added.

## Decisions

- 2026-10-31 — fast lane is Qwen3.6-35B-A3B UD-Q4_K_XL (non-thinking) instead of
  Qwen3-Coder-30B-A3B: newer generation, faster on this hardware (kyuz0 benchmarks),
  vendor-reported agentic scores well above gpt-oss-120b. gpt-oss-120b stays the
  accurate lane until an A/B on real tickets says otherwise (`--extra qwen36-q8`).
- 2026-10-31 — juniors run as Paperclip `hermes_local` agents (Paperclip spawns
  `hermes chat` per run) instead of three Hermes gateways/API servers: no ports, no
  invite flow, no `.env` wiring, and Hermes's own multiplexed-gateway limit makes
  the per-profile gateway design impossible anyway.
- 2026-10-31 — the Reviewer records verdicts as a review *comment* + label. GitHub
  allows one machine account per person and refuses self-approval, so formal approval
  is the board's merge.
- 2026-10-31 — 124 GiB GTT (not 128): leaves 4 GiB the GPU cannot pin, so a runaway
  allocation fails cleanly instead of OOM-killing the host.

- 2026-10-31 — second ticket (SPI-2 → SPI-3) round-tripped: CEO routed, pyro delivered
  PR #2 with QA PASS, Watchdog verified, Reviewer approved, CEO reported with a merge
  request, board merged. One miss: the Reviewer (Codex) recorded its approval on the
  Paperclip task only — no review comment and no `reviewer-approved` label on GitHub
  (it followed Paperclip's review-stage procedure and skipped the `gh` steps in its
  AGENTS.md). Fix: the verdict is now one command, `/opt/devco/bin/review-verdict.sh
  approve|changes <pr> <body>`, which posts the comment, sets the label and updates the
  task together; the CEO's hand-back check now verifies the label on GitHub.
- 2026-10-31 — third ticket (SPI-5 → SPI-6, PR #3): the review *loop* worked (the
  Reviewer sent it back once with a precise list, pyro fixed exactly that), but two
  wiring faults showed: (a) after the changes-requested round pyro's status update
  returned HTTP 403 and Paperclip's recovery re-woke it every few minutes for 45 min
  (comments succeed, status writes don't — the task was no longer assigned to pyro);
  the board paused pyro, set the task to In Review by hand and the Reviewer approved;
  (b) the Reviewer again approved on the task without the GitHub comment/label.
  Repo changes: the CEO now puts a missing verdict on the PR itself before reporting;
  the org chart follows the ladder (CEO → Architect → Principal → juniors; QA under the
  CEO); the PR template no longer has a `<task URL>` placeholder.
  Root cause of the 403 (from the Hermes 0.22.5 source, not from a log): Hermes runs every
  chat through one long-lived gateway daemon per host, and tool subprocesses inherit the
  environment of the `hermes chat` that started it. The daemon idles out after 10 min;
  pyro's second run came 4 min after its first, reused the first run's daemon, and so sent
  the first run's PAPERCLIP_API_KEY/RUN_ID -> 403 on every write; each recovery wake kept
  the daemon alive. Fix in config.template.yaml: `gateway.standalone: true` (own gateway
  per profile) + `unmanaged_idle_exit_seconds: 5` (fresh daemon per run).
- 2026-11-01 — the artvault chain (SPI-8, seven tickets) ran overnight: brief (Opus),
  ADR (Fable) and brand (pixel) approved; the backend (pyro) hit three things.
  (a) The stale-gateway problem came back as `agent_run_cancelled`: a run Paperclip had
  cancelled left its Hermes gateway busy (so it never idled out), and the next run's
  commands carried the cancelled run's token. Fix: juniors now run hermes through
  `/opt/devco/bin/hermes-run`, which stops the profile's gateway before every `chat`.
  (b) The Reviewer treated GitHub as unavailable because Paperclip's own prompt tells
  agents to look for a "connection" for any service; it found none and requested one.
  Every agent's instructions now say GitHub is the preinstalled `gh` + SSH, no
  connection ever. (c) The Watchdog (Pi) "fixed" the Reviewer's findings itself and
  pushed a branch — Paperclip's watchdog mandate ("restore a live path") beat our rule.
  It now runs with `--exclude-tools edit,write` and a blunter instruction. Also: the CEO
  held all PRs for one report at the end of the chain, so nobody was asked to merge; it
  now sends a merge card per approved ticket.
- 2026-10-31 — `new-project.sh <name> --python|--node|--stacks`: one command creates
  the GitHub repo in the org as the bot, adds the agents team, pushes the bootstrap
  files to main and registers the Paperclip project; the CEO may run it when a board
  task says "Project: <name> (new; …)". After lockdown, installing it into
  /opt/devco/bin needs sudo (or unlock → install-paperclip.sh → lockdown).
- 2026-10-31 — added a ninth agent, `pixel`: a Codex-backed graphic/UI designer (SVG
  art, palettes/themes, mockups, scripted PNG assets, design review), reporting to the
  Principal with the other juniors; shares the ChatGPT Plus pool with the Reviewer.
- 2026-10-31 — lockdown.sh ran clean (Phase 6). `sudo -n true` still succeeded right
  after because sudo had cached the password typed during step 2; the script now runs
  `sudo -k` and verifies itself.
- 2026-10-31 — the board opened the Principal and the Chief Architect to the CEO
  (no `protected` assignment policy, Architect not paused) so hard work climbs the
  ladder without a human in the loop. The ladder rules in `ceo/AGENTS.md` are now the
  only brake on Max-plan spend; `devco pause` still parks all Claude-backed agents.

- 2026-11-02 — SPI-12 (artvault backend, pyro) stranded after the Reviewer's third round; the
  board's composer did nothing; PR #4 never got a GitHub verdict. Evidence: Paperclip's activity
  log, run records and transcripts, the server journal, pyro's Hermes session store, and the
  Paperclip source at the installed tag (v2026.1023.0; line numbers below are from that tag). The
  write-up was checked by nine independent re-derivations; corrections are folded in.
  (a) **Who emptied the assignee: Paperclip's review policy, not a recovery step.** After three
  consecutive *agent* changes-requested decisions on one review stage the stage escalates to the
  responsible human (`server/src/services/issue-execution-policy.ts`: `DEFAULT_MAX_REVIEW_ROUNDS = 3`
  l.69, escalation l.867-892, `reviewEscalationUserId` = responsibleUserId, else createdByUserId,
  l.457-463): `assigneeAgentId` → null, `assigneeUserId` → the board, status `in_review`, and the
  hold is sticky (l.724-760; another actor changing status or assignee gets 422 "Only the escalated
  reviewer can advance", a comment alone is accepted). Activity log 06:30:56Z: the Reviewer's PATCH
  `{status: in_progress}` became round 3 and escalated; the pending "Connect GitHub" card expired
  with "The task assignment changed" (`issue-thread-interactions.ts:4748-4755`) and the Reviewer's
  run was cancelled `issue_reassigned`. A *human* decision resets the counter (l.867-868), which is
  why reassigning as the board worked and why `devco unstick` is a board PATCH.
  The 403s: pyro's hand-back at 05:28Z reassigned the task to the Reviewer, which cancels pyro's own
  run (8932ed3c). The Hermes gateway that run had started (pid 107326, 05:16:49Z–06:15:20Z per
  `~/.hermes/profiles/pyro/logs/gateway-exit-diag.log`) was kept busy by the cancelled run's own
  orphaned turn, so the 5 s idle exit never came and the next two runs (10dd782b, b4b4ba84, both
  recorded "succeeded") inherited `PAPERCLIP_RUN_ID=8932ed3c…` — every write 403
  `agent_run_cancelled` (`middleware/auth.ts:403-413`; journal 05:29–06:14Z, the first three from
  the cancelled run's own turn). Paperclip's recovery woke pyro again; on a fresh gateway
  (pid 123097, 06:16:24Z) it "restored" the task into review with a new head, the Reviewer found a
  new traversal, round 3. `hermes-run` (11:16 PST) stops the profile's gateway before each chat, so
  a cancelled run can no longer lend its credentials to the next one.
  (b) **The composer never sends.** The task page used on this box (`enableClassicTaskInterface`
  off) submits through `ui/src/components/task-chat/TaskChatComposer.tsx:1039`
  `attemptId = crypto.randomUUID();` — evaluated before anything is sent (the classic
  `IssueChatThread.tsx:5044` has the same line). Browsers define `crypto.randomUUID` only in secure
  contexts (HTTPS or localhost); the server speaks plain HTTP on 0.0.0.0:3100 and the board's two
  sessions are Chromium-based (Opera desktop and Android), so it throws, the catch block puts the
  draft back, no toast, no request. The journal for both windows the board had the task open
  (06:49–06:50Z, 19:04–19:20Z) shows only GETs and `POST /issues/<id>/read`; not one browser comment
  or reassignment has ever reached the server (the single user comment is the CLI unstick). The
  bundle `@paperclipai/server/ui-dist/assets/index-*.js` has 18 unguarded calls; upstream has a safe
  `ui/src/lib/uuid.ts createUuid()` ("also work on plain-HTTP LAN") that these call sites do not
  use, at HEAD too — worth an upstream issue. Workaround: a tunnel,
  `ssh -L 3100:127.0.0.1:3100 geoff@hermes` → http://localhost:3100 (or Chrome's "Insecure origins
  treated as secure" flag for the LAN origin). Status/assignee changes from the task page do not go
  through that path and keep working.
  (c) **The Reviewer and GitHub — the real cause is in create-company.sh.** Every one of the ten
  Reviewer runs before 2026-11-02 (and 32 of the Watchdog's 35) ran with **no managed instructions
  at all**: `create-company.sh`'s update sends `replaceAdapterConfig: true` with an adapterConfig
  that lacks Paperclip's own bundle keys, so `instructionsFilePath` is dropped
  (`routes/agents.ts:5231-5236` merges only without that flag) and the adapter injects nothing
  (adapter events: `instructionsChars 0`, only the repo-AGENTS note). The keys come back only when
  the same run also rewrites the entry file (19:54 PDT, 11:17 PST), and the next re-run that
  changes nothing strips them again (20:29 PDT). So the Reviewer followed Paperclip's generic skill:
  it recorded verdicts by PATCHing the task (`gh pr view` ran read-only in six runs; no
  `gh pr review/edit` ever), and in SPI-12 rounds 2 and 3 it called `connections_search` +
  `connection_request github` through the managed MCP gateway, was told a card had gone to the
  board, and treated GitHub as unavailable. The Watchdog's "fixing the findings itself" (NOTES above)
  has the same explanation. Separately, `/opt/devco/bin/review-verdict.sh` was never on the box:
  the installer line was added (16:22 PDT) after the box was installed (15:04 PDT), later one-off
  `sudo install`s skipped it, lockdown made the directory root-owned. The first Reviewer run that
  ever saw its AGENTS.md (01:27Z today, after the 11:17 PST rewrite re-wired it) did exactly what it
  says — `gh pr diff/view`, QA, the verdict script — and hit "No such file or directory".
  Fixes: `create-company.sh` carries the bundle keys through the replace, re-points any agent that
  lost them (`agent instructions-path:update`) and exits non-zero if one stays unwired;
  `devco status` reports agents running without instructions, Paperclip copies that differ from
  the repo, every script the instructions name that is not installed, `/opt/devco/bin` files
  behind the repo, and tasks waiting on the board (unassigned, escalated, or parked on an agent
  with no run for 10 min); `sudo bash ~/devco-infra/bin/devco install-bin` reinstalls everything
  `install-paperclip.sh` installs (one list, parsed from the installer); the Reviewer's failure rule
  now says exactly how to stop (one PATCH, `in_review`, "Review verdict wiring failure").
  (d) **`devco unstick <ticket>`** shows the task's state (status, assignees, review participant and
  round count, live runs, pending cards, open recovery actions, execution locks) and the plan, then:
  cancels live runs only with `--cancel-runs` (and stops if any survive), cancels pending question
  cards (connection cards cannot be cancelled by the board; they expire when the assignee changes),
  force-releases locks, stops a Hermes target's gateway unless it is busy, PATCHes status + assignee
  + comment as the board and waits for the run, waking the agent on the issue if Paperclip does
  not. Target and status follow the review stage: an agent holding the stage is woken back into
  `in_review`; an escalated review goes back to the engineer with `in_progress` (Paperclip routes a
  board `in_progress` there whatever `--to` says, so that is refused); otherwise the return
  assignee or current agent. `--dry-run` first. Done/cancelled tasks are refused.
  Also seen, not fixed: every Codex run first tries `python` (exit 127) before `python3`; the
  Watchdog re-ran three times in five minutes on PR #5 while the Reviewer was parked.

## Things to check after the first week

See `docs/first-week.md`.
