---
name: homelab-change-safety
description: The read-only-first, reversible-change procedure for anything running on the NAS, the model box, or the network. Use before touching any live service, port, DNS entry, or proxy host.
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [safety, change-management, homelab, rollback, backups]
---

# Homelab change safety

## Overview
The homelab serves real traffic (media, DNS, auth, the model gateway the whole
company depends on). A bad change here takes the company down with it. So:
discover, plan, back up, change, verify, record. In that order, every time.

## When to Use
Any ticket that would change a running container, a systemd unit, a reverse-proxy
host, a DNS record, a firewall rule, or a file under a live config directory.

## Procedure
1. **Discover (read-only).** Write the current state on the ticket before touching
   anything:
   ```bash
   docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
   docker inspect <name> --format '{{json .Mounts}}' | jq
   systemctl --user list-units --type=service --state=running   # on the model box
   ss -ltnp | grep -E ':(80|443|3100|8080|864[2-9])\b'
   ```
2. **Plan.** On the ticket: what changes, what it affects, how to roll back, and
   how you'll verify. If rollback is "reinstall", stop and ask.
3. **Back up** what the change touches: copy the config directory with a
   timestamp, note the current image tag, `git stash`/commit the repo state.
   ```bash
   cp -a /path/to/config "/path/to/config.bak.$(date +%Y%m%d-%H%M%S)"
   ```
4. **Window.** Changes to live services wait for the board's approval on the
   ticket and the window the board names. Model-gateway changes also require
   that no agent is mid-task (`curl -s http://127.0.0.1:8080/running`).
5. **Change** the smallest thing. One service at a time. Reload before restart,
   restart before recreate, recreate before anything bigger.
6. **Verify** with the check you wrote in step 2 (a `curl`, a `docker logs --tail
   50`, a healthcheck turning green). Paste the evidence.
7. **Record** on the ticket: what changed, when, how to roll back, and update the
   stack's README if the topology changed.

## Hard stops (ask the board, do not proceed)
- Anything exposing a service to the internet.
- DNS, Cloudflare, Authelia/SSO, or certificate changes.
- Anything touching `/mnt/user` data shares.
- Deleting volumes, images, or backups.
- Changing the model gateway while the company has tasks in flight.

## Pitfalls
- Assuming the compose file in git matches what's running. Check `docker inspect`.
- `docker compose down` on the wrong directory (it takes the whole stack down).
- Restarting the DNS container and losing name resolution for the rest of the job.

## Verification
Before/after state recorded, backup path on the ticket, verification output
pasted, rollback path named.
