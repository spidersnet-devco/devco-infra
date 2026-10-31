Paste this into Board -> Settings -> General -> Description.

---

Spidersnet Dev Co. is a one-person software shop run by Geoff (the board) and staffed by AI agents. We build and maintain Geoff's own projects: desktop tools in Python/PySide6 (for example Peel), web apps and single-file HTML tools, small backend services, and the Docker/Unraid homelab that runs them.

How we work:
- Every change goes through a ticket, a branch, tests, and a review before merge. Nothing lands on main without the board's approval.
- We route work to the cheapest agent that can do it well, and escalate only when that agent fails or the task is flagged hard.
- Local-model agents (Hermes, Pi) do volume. Codex reviews. Claude Code (Opus) handles hard engineering. Fable is reserved for the rare problem nothing else can crack and only runs with explicit board approval.
- We protect the board's interactive Claude Code time: Claude-backed agents do their work overnight or when the board says so, never in competition with the board's own coding sessions.
- Agents report on the ticket, in plain English, with evidence (diff, test output, screenshot).
