#!/usr/bin/env bash
# /opt/devco/bin/hermes-run — what Paperclip calls instead of `hermes` for the juniors.
#
# Hermes 0.22 runs every chat through a gateway daemon, and the shell commands an agent
# runs inherit the environment of the `hermes chat` that STARTED that daemon. Paperclip
# hands each run its own PAPERCLIP_API_KEY / RUN_ID / TASK_ID in the environment, so a
# daemon left over from an earlier run makes every Paperclip call fail (403,
# "agent_run_cancelled" when that earlier run was cancelled). The profile config makes
# each gateway standalone and short-lived, but a daemon still busy with a session from a
# run Paperclip already killed never goes idle. So: before every run, stop this profile's
# gateway if one is running, then exec the real hermes with the same arguments; the
# gateway that `hermes chat` starts next carries this run's environment.
#
# Paperclip sets HERMES_HOME to the profile (agent.json env), so `gateway stop` only
# touches that profile's own gateway. Harmless when none is running.
set -uo pipefail
HERMES="${DEVCO_HERMES_BIN:-$HOME/.local/bin/hermes}"
if [[ -n "${HERMES_HOME:-}" && "${1:-}" == "chat" ]]; then
  "$HERMES" gateway stop >/dev/null 2>&1 || true
  sleep 1   # the client below waits for a draining gateway itself; this just avoids racing the stop
fi
exec "$HERMES" "$@"
