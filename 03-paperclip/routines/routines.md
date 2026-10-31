# Routines (Paperclip -> Routines -> New)

Both routines run on local-model agents so they cost nothing. Neither wakes a
Claude-backed agent. Schedules are in your local time; pick quiet hours.

## 1. Nightly QA sweep — assign to: Watchdog — schedule: daily 02:10

```
Run /opt/devco/qa-run.sh against every repository under /opt/devco/repos on its
main branch. For each repo, record PASS or FAIL. For every FAIL, create a task
assigned to the CEO titled "QA failure: <repo> <date>" containing the failing
section of the output verbatim (no more than 60 lines) and a one-line guess at
the cause. Do not attempt to fix anything. Finish by posting a one-line summary
on this routine's task: "<n> repos checked, <m> failing".
```

## 2. Daily standup — assign to: ops — schedule: weekdays 07:40

```
Compile a standup for the board. Using the Paperclip API (your paperclip skill),
list: tasks completed in the last 24 hours (with who did them), tasks currently
in progress and who has them, tasks blocked and why, and any task that has been
open longer than 3 days. Then look at the running models on the local gateway
(http://127.0.0.1:8080/running) and note whether both coder-accurate and
coder-fast are loaded. Post the standup as a single comment on this routine's
task, in this shape:

DONE (24h): ...
IN PROGRESS: ...
BLOCKED: ...
STALE (>3d): ...
GATEWAY: ...
PRS AWAITING THE BOARD: ... (gh pr list --search "review:approved" across org repos, or "none")
MIRROR: last line of  journalctl --user -u mirror-repos -n 1
ONE THING THE BOARD SHOULD DECIDE TODAY: ... (or "nothing")

Keep it under 25 lines. Do not create or modify any task.
```

## 3. (Optional) Weekly skills review — assign to: ops — schedule: Sundays 09:00

```
For each Hermes profile on this machine (pyro, webby, ops), list the skills under
~/.hermes/profiles/<name>/skills/ that were created or modified in the last 7
days (not the bundled ones). Post the list with a one-line description of each
on this routine's task, so the board can review and prune them. Do not delete
or edit any skill.
```

Why this matters: the juniors write their own skills after complex tasks. A weekly
list is how you catch the bad ones before they compound.

## 4. Nightly repo mirror

Not a Paperclip routine: it's a systemd user timer so it keeps running when the
company is paused. See `mirror-repos.timer.md`. The standup (routine 2) should
include the last line of `journalctl --user -u mirror-repos -n 1` so you notice
if it stops.
