---
name: homelab-change-safety
description: Plan reversible changes to live services; the board applies
version: 2.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [homelab, docker, unraid, safety, rollout, rollback]
---

# Homelab change safety

## Overview
The homelab serves real traffic (media, DNS, auth, and the model gateway the whole
company depends on). A bad change there takes the company down with it. You do not
have access to the NAS, the router, DNS or the proxy, and you never try to get it.
Your deliverable is a PR with the definition change **and a rollout note** so good
that the board can apply it in two minutes and undo it in one.

## When to Use
Any ticket whose merged result will change a running container, a systemd unit, a
reverse-proxy host, a DNS record, a firewall rule, or a file under a live config
directory.

## Procedure
1. **Discover from the repo.** Write on the ticket what the repo says is deployed:
   the stack, its images and tags, volumes, ports, dependencies between services.
   If the repo and reality may differ, say so and ask the board for
   `docker ps` / `docker inspect` output; do not guess.
2. **Plan.** On the ticket: what changes, what it affects, how to roll back, and how
   the board will verify. If rollback is "reinstall", stop and ask.
3. **Change the smallest thing** in the definition. One service per PR. Prefer a
   reload over a restart, a restart over a recreate.
4. **Write the rollout note** into the PR body (section `## Rollout`), in this shape:
   ```
   Backup:    cp -a /mnt/user/appdata/<stack> /mnt/user/appdata/<stack>.bak.$(date +%F)
   Apply:     cd /mnt/user/appdata/<stack> && git pull && docker compose up -d <service>
   Verify:    curl -fsS http://<host>:<port>/health ; docker logs --tail 50 <service>
   Rollback:  git checkout <previous-sha> -- compose.yaml && docker compose up -d <service>
   Window:    any time / off-hours / needs the model gateway idle (curl -s 127.0.0.1:8080/running)
   ```
5. **Validate** what you can locally: `docker compose -f <file> config -q`, shellcheck
   on scripts, `/opt/devco/bin/qa-run.sh .`. Paste the result in the PR's QA section.
6. **Record.** If the topology changed, update the stack's README in the same PR.

## Hard stops (ask the board, do not proceed)
- Anything exposing a service to the internet.
- DNS, Cloudflare, Authelia/SSO, or certificate changes.
- Anything touching `/mnt/user` data shares (as opposed to appdata config).
- Deleting volumes, images, or backups.
- Any change to this box's model gateway config (`/opt/llama-swap/config.yaml`);
  that file is the board's.

## Pitfalls
- Assuming the compose file in git matches what's running; say when you're unsure.
- A rollout note that only says "restart it". Name the exact commands and the sha.
- Forgetting that restarting the DNS container breaks name resolution for
  everything else on the LAN mid-rollout; order matters in the note.

## Verification
PR has the definition change, a `## Rollout` section with Backup/Apply/Verify/
Rollback/Window, QA PASS, and no live system was touched by you.
