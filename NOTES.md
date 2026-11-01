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

## Things to check after the first week

See `docs/first-week.md`.
