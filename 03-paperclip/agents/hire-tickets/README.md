# Hire tickets

Each file is a plain-English ticket. Create a task in Paperclip, assign it to the CEO,
paste the text in. The CEO turns it into a hire request; approve it under
**Approvals** (Board -> Settings -> General -> Hiring must have "Require board
approval for new hires" ON, which install-paperclip.sh told you to set).

Order:

1. `reviewer.md` (Codex) — needs `codex login` done on the box first.
2. `watchdog.md` (Pi, local) — needs llama-swap running.
3. `principal-engineer.md` (Claude Code, opus)
4. `chief-architect.md` (Claude Code, fable) — optional at first; add when you hit the first wall.

The three Hermes juniors are NOT hired through tickets. They are external agents
that join via an invite: see `invite-hermes-juniors.md`.

After every hire, check the new agent's **Permissions / Trust** tab. If the hiring
skill picked a low-trust preset that requires a sandbox, set **Trust preset ->
Standard** or the agent fails on its first run.
