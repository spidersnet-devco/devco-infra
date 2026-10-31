# devco-infra — instructions for Claude Code running ON the Hermes box

This repo builds and maintains the Spidersnet Dev Co. agent company on the
MINISFORUM MS-S1 Max. You are being run by Geoff (the board) over SSH on that box.
`README.md` is the runbook; this file is how you are expected to execute it.

## How to work this repo

- Execute **one phase at a time**, only the phase Geoff names. Phases are in README.md.
- Before each phase: read the scripts that phase runs. Say in two lines what they
  will do. Then run them.
- When a script fails: fix the script **in this repo** (not an ad-hoc command),
  explain the fix in one line, commit it with a message starting `fix:`, and
  continue. The repo must end up matching the real box.
- Machine-specific values live in `/opt/devco/devco.env` (not committed). Edit that
  file for this box; edit `devco.env.example` only when a *new* variable is needed.
- Keep a running `NOTES.md` at the repo root: what deviated from the runbook on this
  box, exact model filenames, versions installed, anything the next person needs.
  Commit it as you go.

## Stop and ask before

- Rebooting, or anything that changes GRUB / kernel parameters (Phase 0 ends in a reboot;
  do the config, show the diff, then stop and let Geoff reboot).
- Any browser login (`claude`, `codex login`, `gh auth login`, Paperclip claim). Print the
  command, tell Geoff to run it in his own terminal, wait.
- Deleting anything outside this repo's working tree, `/tmp`, or a scratch dir you made.
- Downloading more than ~10 GB that the runbook didn't already call for.
- Changing anything under `/opt/llama-swap/config.yaml` once agents are live
  (the whole company depends on that gateway).
- Touching the NAS, DNS, the reverse proxy, or anything not on this box.

## Never

- Commit secrets. `.env`, `devco.env`, keys, tokens: never. `.gitignore` covers them;
  check `git status` before every commit anyway.
- Push to `main` from an agent context later on; for *this* setup work, Geoff is driving
  and direct commits to `main` are fine.
- Use `sudo` for anything the scripts don't already use it for without saying why.
- Run `rm -rf`, `docker system prune`, `systemctl --user reset-failed` wholesale, or
  anything else broad and destructive without listing exactly what it hits first.

## Verification is part of every phase

A phase is done when its check passes, not when its script exits 0:

| Phase | Done means |
|---|---|
| 0 | `/opt/devco/devco.env` edited; GRUB diff shown; Geoff has rebooted; `mem_info_gtt_total` ≈ 128 GB |
| 1 | `curl 127.0.0.1:8080/running` lists `coder-accurate` and `coder-fast`; both answer a chat completion with tool calling on |
| 2 | Paperclip UI reachable on the LAN IP; `claude --version` ≥ 2.1.255; `codex --version` works; Pi config points at the gateway |
| 3 | `hermes -p pyro doctor` (and webby, ops) clean; three gateway ports listening |
| 4+ | per README |

Report each phase to Geoff as: what ran, what you changed in the repo, what the
check showed, what's next.
