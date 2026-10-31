---
name: ci-and-deploy
description: CI workflows, deploy scripts, systemd units, backups
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [ci, github-actions, systemd, deploy, backup, scripts]
---

# CI and deploy

## Overview
Automation here is small shell scripts and systemd user units, plus GitHub
Actions where a repo lives on GitHub. Boring and inspectable beats clever.

## When to Use
Tickets that create or change a workflow file, a deploy/backup script, a cron or
systemd timer, or a service unit.

## Procedure
1. **Scripts** are bash with the standard header and are shellcheck-clean:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   ```
   Parameters via arguments or a sourced env file, never hardcoded paths to
   someone's home directory. Log what you're doing; exit non-zero on failure.
2. **Scheduling** uses systemd user timers (not crontab) on this box, so they show
   in `systemctl --user list-timers` and survive reboots with linger enabled:
   ```ini
   # ~/.config/systemd/user/<job>.service
   [Unit]
   Description=<what it does>
   [Service]
   Type=oneshot
   ExecStart=/opt/devco/bin/<job>.sh
   ```
   ```ini
   # ~/.config/systemd/user/<job>.timer
   [Unit]
   Description=Run <job> nightly
   [Timer]
   OnCalendar=*-*-* 03:15:00
   Persistent=true
   [Install]
   WantedBy=timers.target
   ```
   `systemctl --user daemon-reload && systemctl --user enable --now <job>.timer`
3. **GitHub Actions**: one workflow per concern (`ci.yml`, `release.yml`), pinned
   action versions (`actions/checkout@v4`), cache the package manager, run the
   same commands `/opt/devco/bin/qa-run.sh` runs so CI and local agree.
4. **Deploys** are pull-based: the NAS pulls the tagged image/branch; nothing
   pushes into the NAS from CI. The deploy script validates (`compose config`),
   backs up, applies, verifies (healthcheck), and prints a rollback command.
5. **Backups**: restic or a plain `tar` + checksum to the NAS backup share,
   with retention stated in the script header; test a restore once and record
   the command on the ticket.
6. Hand back with the unit/workflow file, the first successful run's output
   (`journalctl --user -u <job> -n 50` or the Actions log tail), and the
   rollback command.

## Pitfalls
- Timers without `Persistent=true` (missed runs while the box was off never happen).
- Scripts that assume `cwd`. Use absolute paths or `cd "$(dirname "$0")"`.
- Secrets in workflow YAML. Use the repo's secrets store and reference by name.
- `set -e` with a pipeline whose first command fails silently: use `pipefail`.

## Verification
shellcheck clean; the timer/workflow ran once successfully with output on the
ticket; rollback command recorded.
