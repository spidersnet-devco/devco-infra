# devco-infra — instructions for Claude Code running ON the Hermes box

This repo builds and maintains the Spidersnet Dev Co. agent company on the
MINISFORUM MS-S1 Max. You are being run by Geoff (the board) over SSH on that box.
`README.md` is the runbook; this file is how you are expected to execute it.

Most of the runbook runs itself: the unattended install (`00-unattended/`) does
Phases 0, 1 and the no-login parts of 2 and 3 on first boot. Your usual job is
therefore the logins, `create-company.sh`, the first projects, lockdown, and fixing
whatever the bootstrap log says failed.

## How to work this repo

- First command on a fresh box: `devco status` (or `/opt/devco/bin/devco status`)
  and `cat /opt/devco/bootstrap.log | tail -50`. Say what state the box is in.
- Execute **one phase at a time**, only the phase Geoff names. Phases are in README.md.
- Before each phase: read the scripts that phase runs. Say in two lines what they
  will do. Then run them.
- When a script fails: fix the script **in this repo** (not an ad-hoc command),
  explain the fix in one line, commit it with a message starting `fix:`, and
  continue. The repo must end up matching the real box.
- Machine-specific values live in `/opt/devco/devco.env` (not committed). Edit that
  file for this box; edit `devco.env.example` only when a *new* variable is needed.
- Keep a running `NOTES.md` at the repo root: what deviated from the runbook on this
  box, exact versions (`devco versions`), anything the next person needs. Commit it
  as you go. IPs, ids and anything box-specific go in `NOTES.local.md` (gitignored).
- The company's own definition is `03-paperclip/agents/`. Changing an agent means
  editing there and re-running `create-company.sh`, never clicking it into the UI
  only (the UI change would be lost on the next run).

## Stop and ask before

- Rebooting, or anything that changes GRUB / kernel parameters (do the config, show
  the diff, then stop and let Geoff reboot).
- Any browser login (`claude auth login`, `codex login`, `gh auth login`, Paperclip
  claim, `paperclipai auth login`). Print the command, tell Geoff to run it in his
  own terminal (`03-paperclip/logins.sh` batches them), wait.
- Deleting anything outside this repo's working tree, `/tmp`, or a scratch dir you made.
- Downloading more than ~10 GB that the runbook didn't already call for
  (`download-models.sh --extra ...` counts).
- Changing anything under `/opt/llama-swap/config.yaml` once agents are live
  (the whole company depends on that gateway). After lockdown it is root-owned.
- Running `lockdown.sh` (it changes sudo for Geoff's account) or `devco unlock`.
- Touching the NAS, DNS, the reverse proxy, or anything not on this box.

## Never

- Commit secrets. `.env`, `devco.env`, keys, tokens: never. `.gitignore` covers them;
  run `git status` and read the list before every commit anyway.
- Push to `main` from an agent context later on; for *this* setup work, Geoff is driving
  and direct commits to `main` are fine (after lockdown: `DEVCO_ALLOW_MAIN=1 git push`).
- Use `sudo` for anything the scripts don't already use it for without saying why.
- Run `rm -rf`, `docker system prune`, `systemctl --user reset-failed` wholesale, or
  anything else broad and destructive without listing exactly what it hits first.
- Use `sudo npm install -g` (breaks Claude Code's self-update; npm globals live in
  `~/.npm-global`, Claude Code uses its native installer).

## Verification is part of every phase

A phase is done when its check passes, not when its script exits 0:

| Phase | Done means |
|---|---|
| 0 | `/opt/devco/devco.env` has the real `DEVCO_LAN_IP`; `cat /proc/cmdline` shows `ttm.pages_limit`; `mem_info_gtt_total` ≈ total RAM (≥ 120 GB; ~64 GB means it did not apply) |
| 1 | `curl 127.0.0.1:8080/running` shows `coder-accurate` and `coder-fast` both `"state":"ready"`; `install-llama-swap.sh`'s tool-calling smoke test prints `tool call OK` for both |
| 2 | Paperclip UI reachable at `http://<LAN IP>:3100` and claimed; `paperclipai service status` running; `paperclipai auth whoami` works; `claude --version` ≥ 2.1.257 and `claude auth status` logged in; `codex login status` logged in; `pi --list-models \| grep devco/`; `gh auth status` = the bot; `create-company.sh` ran clean and `devco status` lists all 8 agents with the right models (CEO = claude-sonnet-5-5) |
| 3 | `HERMES_HOME=~/.hermes/profiles/<p> hermes doctor` clean for pyro, webby, ops; `create-profiles.sh --smoke` answers for all three; in Paperclip each junior shows adapter `hermes_local` |
| 4 | `clone-project.sh peel --python` done; Paperclip shows the project with codebase `/opt/devco/repos/peel`; `qa-run.sh /opt/devco/repos/peel` prints a verdict |
| 5 | First ticket round-tripped: PR opened by the bot, Reviewer comment + `reviewer-approved` label, Watchdog comment, Geoff merged |
| 6 | `lockdown.sh` ran; `sudo -n true` fails; `git push` to main is refused by the hook |

Report each phase to Geoff as: what ran, what you changed in the repo, what the
check showed, what's next.
