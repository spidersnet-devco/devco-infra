# Routines

`create-company.sh` creates these three Paperclip routines from the `.md` files here
(the file is the routine's prompt). All three run on local models, so they cost
nothing and never wake a Claude-backed agent. Schedules are in the box's time zone.

| Routine | Assigned to | Schedule | Prompt |
|---|---|---|---|
| Nightly QA sweep | Watchdog (Pi, local) | 02:10 daily | `nightly-qa.md` |
| Daily standup | ops (Hermes, local) | 07:40 weekdays | `standup.md` |
| Weekly skills review | ops (Hermes, local) | 09:00 Sundays | `skills-review.md` |

All three live in the `ops` project (this repo's clone on the box), because a
routine needs a project for its working directory.

To change one: edit the `.md`, then in Paperclip → Routines → the routine → edit
the description (or delete the routine and re-run `create-company.sh`, which only
creates routines that don't exist yet).

## Not a routine: the nightly repo mirror

`mirror-repos.sh` runs as a systemd user timer (`mirror-repos.timer.md`) so it keeps
working when the company is paused. The standup reports its last line.

## The QA script

`qa-run.sh` is installed to `/opt/devco/bin/qa-run.sh`. It is the "QA agent" that is
not an LLM: lint + tests + compose validation + shellcheck, with a PASS/FAIL verdict.
See its header for the three ways to call it (a path, a PR URL, or `--all-main`).
