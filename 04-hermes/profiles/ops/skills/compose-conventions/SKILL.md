---
name: compose-conventions
description: How Docker Compose stacks are written and laid out at Spidersnet Dev Co. (Unraid appdata layout, env files, healthchecks, networks). Use for any ticket that touches a compose file or a container.
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [docker, compose, unraid, containers, homelab]
---

# Compose conventions

## Overview
Stacks are plain `docker compose` projects kept in git, one directory per stack,
deployed to the NAS's appdata share. Consistency is what lets the board eyeball a
diff on a phone and approve it.

## When to Use
Any ticket touching `compose*.yml`, a `Dockerfile`, an `.env.example`, or a
container's config.

## Quick Reference
```
stacks/<name>/
  compose.yml          # the stack
  .env.example         # every variable, with safe defaults, committed
  .env                 # real values, GITIGNORED, never in a ticket
  README.md            # what it is, ports, volumes, how to update
```
```bash
docker compose -f stacks/<name>/compose.yml config -q   # validate
docker compose -f stacks/<name>/compose.yml pull         # staging box only
```

## Procedure
1. Find the stack's directory in the repo and read its README and `.env.example`
   before anything else.
2. **Images are pinned** to a version tag (`image: ghcr.io/x/y:1.4.2`), never
   `latest`. Upgrading a tag is its own ticket with the changelog link in it.
3. **Volumes** use the NAS appdata convention the README names (for example
   `/mnt/user/appdata/<name>:/config`). Media/data shares are read-only
   (`:ro`) unless the service must write.
4. **Networks:** services that only talk to the reverse proxy sit on the shared
   proxy network and publish no host ports. Publish a port only when the README
   says the service is reached directly on the LAN.
5. **Every long-running service has a `healthcheck`** and `restart: unless-stopped`.
6. **Secrets** come from `.env` via `${VAR}` references. If you need a new one,
   add it to `.env.example` with a placeholder and say so in the hand-back.
7. **Resource limits** (`mem_limit`, `cpus`) on anything that can run away (media
   transcoders, AI workloads).
8. Validate with `docker compose config -q`, run `/opt/devco/qa-run.sh`, hand back
   with the diff and a one-paragraph "what changes when this is deployed".
9. **Deploying** is a separate, board-approved ticket. You do not deploy as part
   of writing the change.

## Pitfalls
- `latest` tags (the stack silently changes on the next pull).
- Host-mounting a directory that doesn't exist yet (Docker creates it as root).
- Two stacks publishing the same host port.
- Putting the real `.env` in git. Check `git status` before committing.

## Verification
`docker compose config -q` is clean, image tags are pinned, `.env` is not in the
diff, README updated if ports/volumes changed.
