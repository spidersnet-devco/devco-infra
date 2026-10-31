# NOTES — what actually happened on this box

Claude Code (or you) keeps this current while running the runbook. Facts that are
box-specific and not for a public repo (LAN IPs, Paperclip ids, MACs) go in
`NOTES.local.md`, which is gitignored.

## Versions installed

Paste `devco versions` here after each phase, with the date.

```
(not installed yet)
```

## Deviations from the runbook

- (none yet)

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

## Things to check after the first week

See `docs/first-week.md`.
