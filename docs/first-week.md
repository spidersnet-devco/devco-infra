# The first week

What to expect, what to check, and what to tune once the company is running. Ten
minutes a day on your phone is enough.

## Day 1 — the first ticket round trip

Give the CEO one small ticket (README Phase 5). Watch for these, in order:

1. **CEO run appears** in the task's activity. If it sits in Approvals as "CEO
   Strategy", approve it. If it fails with `claude_cli_version_incompatible`, run
   `claude update` on the box.
2. **A junior ticket exists** with a Project set and a "Done means" checklist. If the
   CEO wrote a path instead of setting the Project field, tell it on the task; it
   learns from the correction for that thread only, so also fix `ceo/AGENTS.md` if the
   wording was unclear and re-run `create-company.sh`.
3. **pyro's run log** starts with `[hermes] Starting Hermes Agent (model=coder-accurate`.
   Anything else (`auto`, a provider name) means the agent config drifted; re-run
   `create-company.sh`.
4. **A PR appears** on GitHub from the bot with the five sections. If the junior wrote
   "QA: PASS" but the PR has no QA output, the Reviewer should bounce it; if it
   doesn't, tighten `reviewer/AGENTS.md`.
5. **Reviewer comment + label**, **Watchdog comment**, **CEO report**. You merge on
   GitHub and close the ticket in Paperclip.

If any step stalls for more than ~20 minutes: `devco status`, then the agent's run log
in Paperclip (Agents → agent → Runs).

## Days 2–3 — watch the costs

- Company → **Costs**: the Claude 5-hour and 7-day windows, and the ChatGPT window.
  The CEO should be a thin line. If it isn't, it is being woken too often: check the
  "max concurrent runs = 1" and "timer off" settings survived, and that no routine is
  assigned to it.
- Your own interactive Claude Code sessions share the window. `devco pause` before,
  `devco resume` after. If you forget, the worst case is a stalled Principal run, not a
  bill.
- Plus (Codex) runs dry fastest. One review per PR is the budget; if the Reviewer
  re-reads whole repos, its instructions need the "diff only" line reinforced.

## Days 3–5 — quality of the juniors

- Read two or three merged PRs properly. Are the tests real? Did the junior touch only
  what the ticket named? Common first-week failure modes and the fix:
  - *Junior rewrites unrelated code*: add the files to "Do not touch" in the ticket
    template the CEO uses (ceo/AGENTS.md → "How tickets are written").
  - *Junior stops early with "cannot complete"*: often a missing checklist item or a
    repo without `AGENTS.md`. Merge the bootstrap PR from `clone-project.sh`.
  - *Junior loops*: the CEO should escalate on the second bounce. If it keeps
    reassigning the same junior, the rule in ceo/AGENTS.md was not followed; quote it
    on the task.
- Sunday: read the **Weekly skills review** task. Delete any skill under
  `~/.hermes/profiles/<name>/skills/` that encodes a wrong lesson. Skills from this
  repo (`04-hermes/profiles/*`) are not listed there; edit those in git.

## Day 5–7 — the first escalation

Sooner or later a ticket is too hard for a junior. The intended path:

1. The Reviewer bounces it twice, or the junior blocks it with a write-up.
2. The CEO puts a brief on the ticket and asks you in your **Inbox** to escalate.
3. You read the brief (one minute) and assign the task to the Principal Engineer
   yourself. Only you can; that is the protection.
4. Opus does the work, hands back a PR like anyone else, and leaves a note the juniors
   can learn from. The `ops` profile's skills-review will show you if a skill came out of it.
5. If the Principal fails too, the same path leads to the Chief Architect, which starts
   paused: `devco resume`, assign, `devco pause` again when it's done.

Check after the first escalation: Company → Costs. One Opus ticket should be visible
but not alarming. If it burned a large share of the 5-hour window, lower
`maxTurnsPerRun` in `principal-engineer/agent.json`.

## End of week 1 — housekeeping

- `devco backup` ran nightly? `devco status` shows the mirror line? If not,
  `devco mirror-timer`, `devco backup --install-timer`, and check the NAS mount.
- `lockdown.sh` has run (README Phase 6). `sudo -n true` should fail.
- Paperclip → Company → **Export**, scrub LAN IPs and ids, commit as
  `03-paperclip/company-export/`. A rebuild can then import it instead of re-running
  `create-company.sh`.
- Update `NOTES.md`: versions (`devco versions`), anything that deviated.
- Decide on the fast lane: if the juniors' PRs have been good, try
  `download-models.sh --extra qwen36-q8` and A/B the accurate lane on a few real
  tickets (the comments in `02-models/llama-swap.yaml` say how). Don't change the
  gateway while a ticket is running.

## Things that are normal

- The first run of each agent is slow: Paperclip installs its skills, Hermes compiles
  its prompt, the model loads the long system prompt once.
- A junior asking a question on the ticket instead of finishing. That is cheaper than
  a wrong guess; answer it.
- The Watchdog reopening a task the Reviewer approved. Read what it found; it is
  usually right about the checklist and wrong about the importance.
- Codex showing "quota exhausted" for an hour at the end of a busy day. It comes back.
