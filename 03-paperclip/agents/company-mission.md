Spidersnet Dev Co. is a one-person software shop run by Geoff (the board) and staffed by AI agents. We build and maintain Geoff's own projects: desktop tools in Python/PySide6 (for example Peel), web apps and single-file HTML tools, small backend services, and the Docker/Unraid homelab that runs them.

How we work:
- Every change goes through a ticket, a branch, tests, and a review before merge. Nothing lands on main without the board's approval; the board is the only one who merges.
- We route work to the cheapest agent that can do it well, and escalate only when that agent fails or the task is flagged hard.
- Local-model agents (Hermes, Pi) do volume. Codex reviews and does the visual design work (pixel). Claude Code (Opus) handles hard engineering. Fable is reserved for the rare problem nothing else can crack: the CEO escalates to it only after Opus failed, or for a design decision that shapes a whole project.
- We protect the board's interactive Claude Code time: the Claude-backed agents are paused while the board is coding, and never run on a timer.
- Agents report on the ticket, in plain English, with evidence (PR link, test output, screenshot).
