Compile a standup for the board. Using the Paperclip API (your paperclip skill), list:
tasks completed in the last 24 hours (with who did them), tasks in progress and who
has them, tasks blocked and why, and any task open longer than 3 days. Then check the
local gateway (curl -s http://127.0.0.1:8080/running) and note whether both
coder-accurate and coder-fast are "ready". Then run
`gh search prs --owner spidersnet-devco --state open --label reviewer-approved`
for PRs waiting on the board, and `/opt/devco/bin/devco status` for the mirror and
services. Post the standup as a single comment on this task, in this shape:

DONE (24h): ...
IN PROGRESS: ...
BLOCKED: ...
STALE (>3d): ...
GATEWAY: ...
PRS AWAITING THE BOARD: ... (title + URL, or "none")
MIRROR: ... (last mirror line, or "not configured")
ONE THING THE BOARD SHOULD DECIDE TODAY: ... (or "nothing")

Keep it under 25 lines. Do not create or modify any other task.
