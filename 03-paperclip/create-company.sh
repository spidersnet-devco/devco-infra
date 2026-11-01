#!/usr/bin/env bash
# 03-paperclip/create-company.sh
# Builds (or updates) the whole company in Paperclip from 03-paperclip/agents/,
# through Paperclip's own CLI. Run once after the logins; re-run after editing
# anything under agents/ (idempotent: agents are matched by name and updated).
#
#   bash 03-paperclip/create-company.sh            # build/update everything
#   bash 03-paperclip/create-company.sh --dry-run  # show the payloads, change nothing
#
# What it sets, and why (each verified against Paperclip's source, Oct 2026):
#   - CEO on claude-sonnet-5-5 (Paperclip's Claude adapter defaults to OPUS when
#     the model is blank, and the setup wizard never asks)
#   - CEO instruction bundle (AGENTS/HEARTBEAT/SOUL) replacing Paperclip's
#     revenue-and-hiring defaults; company goal carrying the mission
#   - "Require board approval for new hires" ON
#   - every agent with timers OFF, wake-on-demand ON, max 1 concurrent run
#   - Principal + Architect reachable by the CEO only up the ladder (rules in ceo/AGENTS.md)
#   - Architect created paused
#   - company budget: warn-only, and local-model (unpriced) usage ALLOWED
#   - an "ops" project (this repo's clone) for the routines, with serialized
#     shared-workspace runs so two agents never edit one checkout at once
#   - the three routines (nightly QA, standup, weekly skills review)
set -euo pipefail
source /opt/devco/devco.env
HERE="$(cd "$(dirname "$0")" && pwd)"
AG="$HERE/agents"
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1

PC() { paperclipai "$@" --api-base "$PAPERCLIP_URL"; }   # --api-base is a per-command option, so it goes last
say() { echo "==> $*" >&2; }      # stderr, so functions can return ids on stdout
need() { command -v "$1" >/dev/null 2>&1 || { echo "!! $1 not found"; exit 1; }; }
need paperclipai; need jq

# ---------------------------------------------------------------- 0. auth ----
if ! PC auth whoami --json >/dev/null 2>&1; then
  cat <<EOF
!! The Paperclip CLI is not logged in as the board. Run (needs a browser, any device):

    paperclipai auth login --api-base $PAPERCLIP_URL

   approve it in Paperclip (signed in as you), then re-run this script.
EOF
  exit 1
fi

# -------------------------------------------------------------- 1. company ---
COMPANY_NAME="${DEVCO_COMPANY_NAME:-Spidersnet Dev Co.}"
COMPANY_ID="$(PC company list --json | jq -r --arg n "$COMPANY_NAME" '[.[] | select(.name==$n)][0].id // empty')"
if [[ -z "$COMPANY_ID" ]]; then
  COMPANY_ID="$(PC company list --json | jq -r '.[0].id // empty')"   # the wizard may have named it differently
fi
if [[ -z "$COMPANY_ID" ]]; then
  say "Creating company: $COMPANY_NAME"
  (( DRY )) || COMPANY_ID="$(PC company create --payload-json "$(jq -n --arg n "$COMPANY_NAME" '{name:$n}')" --json | jq -r .id)"
else
  say "Company: $(PC company get "$COMPANY_ID" --json | jq -r .name) ($COMPANY_ID)"
fi
PCC() { [[ -n "$COMPANY_ID" ]] || { echo "(no company yet)" >&2; return 0; }; PC "$@" --company-id "$COMPANY_ID"; }

# While this script creates agents the hire-approval gate must be OFF (even the board's
# direct creates are refused with 409 while it is on). It is switched on again at the end.
if [[ -n "$COMPANY_ID" ]] && (( ! DRY )); then
  PC company update "$COMPANY_ID" --payload-json '{"requireBoardApprovalForNewAgents":false}' >/dev/null
fi

# ------------------------------------------------------- 2. render helpers ---
render() {  # render <agent-dir> -> JSON payload for create/update (placeholders filled, bundle attached)
  local dir="$1" base files k
  base="$(sed -e "s|__HOME__|$HOME|g" -e "s|__REPOS__|$DEVCO_REPOS|g" \
              -e "s|__GATEWAY__|$MODEL_GATEWAY_URL|g" -e "s|__CEO_ID__|${CEO_ID:-}|g" \
              -e "s|__ARCHITECT_ID__|${ARCHITECT_ID:-}|g" -e "s|__PRINCIPAL_ID__|${PRINCIPAL_ID:-}|g" "$dir/agent.json")"
  files='{}'
  for k in $(jq -r '.instructions[]' <<<"$base"); do
    files="$(jq --arg k "$k" --rawfile v "$dir/$k" '. + {($k): $v}' <<<"$files")"
  done
  jq --argjson files "$files" 'del(.instructions, .paused)
      | . + {instructionsBundle: {entryFile: "AGENTS.md", files: $files}}
      | if (.reportsTo // "") == "" then del(.reportsTo) else . end' <<<"$base"
}
agent_id_by_name() { PCC agent list --json | jq -r --arg n "$1" '[.[] | select(.name==$n)][0].id // empty'; }
agent_id_by_role() { PCC agent list --json | jq -r --arg r "$1" '[.[] | select(.role==$r)][0].id // empty'; }

# Updating an instruction file needs the current content hash (optimistic locking),
# which the CLI's instructions-file:put cannot send. So updates go straight to the API
# with the board token the CLI stored at login (none needed in trusted-local mode).
pc_token() { jq -r --arg b "${PAPERCLIP_URL%/}" '.credentials[$b].token // .credentials[$b + "/"].token // empty' "${PAPERCLIP_AUTH_STORE:-$HOME/.paperclip/auth.json}" 2>/dev/null || true; }
api() {  # api <METHOD> <path> [json-body]
  local tok; tok="$(pc_token)"
  if [[ -n "${3:-}" ]]; then
    curl -fsS -X "$1" "$PAPERCLIP_URL$2" -H 'Content-Type: application/json' ${tok:+-H "Authorization: Bearer $tok"} --data-binary "$3"
  else
    curl -fsS -X "$1" "$PAPERCLIP_URL$2" ${tok:+-H "Authorization: Bearer $tok"}
  fi
}
put_instruction_file() {  # put_instruction_file <agent-id> <bundle-path> <local-file>
  local cur hash payload
  cur="$(api GET "/api/agents/$1/instructions-bundle/file?path=$2" 2>/dev/null || echo '{}')"
  hash="$(jq -r '.contentHash // empty' <<<"$cur")"
  if [[ -n "$hash" && "$hash" == "$(sha256sum "$3" | cut -d' ' -f1)" ]]; then return 0; fi   # unchanged
  payload="$(jq -n --arg p "$2" --rawfile c "$3" --arg h "$hash" '{path:$p, content:$c, baseHash:(if $h=="" then null else $h end)}')"
  api PUT "/api/agents/$1/instructions-bundle/file" "$payload" >/dev/null && say "  updated $2"
}

upsert_agent() {  # upsert_agent <agent-dir>
  local dir="$1" name payload id perms paused
  payload="$(render "$dir")"
  name="$(jq -r .name <<<"$payload")"
  perms="$(jq -c '.permissions' <<<"$payload")"
  paused="$(jq -r '.paused // false' "$dir/agent.json")"
  id="$(agent_id_by_name "$name")"
  [[ -z "$id" && "$dir" == */ceo ]] && id="$(agent_id_by_role ceo)"     # the wizard's CEO has its own name
  if (( DRY )); then echo "--- $name ($( [[ -n "$id" ]] && echo update $id || echo create ))"; jq . <<<"$payload"; return 0; fi
  if [[ -z "$id" ]]; then
    say "Creating agent: $name"
    id="$(PCC agent create --payload-json "$payload" --json | jq -r '.id // empty')"
    [[ -n "$id" ]] || { echo "!! creating agent $name failed (see the API error above)" >&2; exit 1; }
  else
    say "Updating agent: $name ($id)"
    # keep the existing name/role (the wizard's CEO may be called something else); replace config wholesale
    PC agent update "$id" --payload-json "$(jq -c 'del(.permissions, .role, .name, .instructionsBundle) + {replaceAdapterConfig: true}' <<<"$payload")" >/dev/null
    for k in $(jq -r '.instructions[]' "$dir/agent.json"); do
      put_instruction_file "$id" "$k" "$dir/$k" || echo "!! could not update $k for $name" >&2
    done
  fi
  # permissions:update wants the full record
  PC agent permissions:update "$id" --payload-json \
     "$(jq -c '{canCreateAgents: (.canCreateAgents // false), canCreateSkills: (.canCreateSkills // false), canAssignTasks: (.canAssignTasks // true)} + (if .authorizationPolicy then {authorizationPolicy} else {} end)' <<<"$perms")" >/dev/null
  local cur lerr
  cur="$(PC agent get "$id" --json)"
  lerr="$(jq -r '.lifecycleError // ""' <<<"$cur")"
  if [[ -n "$lerr" ]]; then
    # a failed harness check: ask Paperclip to run it again (resume is refused in this state).
    # A bare "verifying" state with no error is a check still in progress: leave it alone.
    api POST "/api/agents/$id/lifecycle/retry" >/dev/null 2>&1 && say "  retrying $name's harness check" || true
  elif [[ "$paused" == "true" ]]; then
    PC agent pause "$id" >/dev/null 2>&1 || true
  elif [[ "$(jq -r .status <<<"$cur")" == "paused" ]]; then
    PC agent resume "$id" >/dev/null 2>&1 && say "  resumed $name" || true
  fi
  echo "$id"
}

# ------------------------------------------------------------------ 3. CEO ---
CEO_ID=""
CEO_ID="$(upsert_agent "$AG/ceo" | tail -1)"
[[ -n "$CEO_ID" || $DRY -eq 1 ]] || { echo "!! CEO id missing"; exit 1; }

# ----------------------------------------------------------------- 4. goal ---
GOAL_TITLE="Build and maintain Geoff's software, cheaply and safely"
if ! PCC goal list --json 2>/dev/null | jq -e --arg t "$GOAL_TITLE" '.[] | select(.title==$t)' >/dev/null; then
  say "Creating company goal (carries the mission; tickets inherit it)"
  (( DRY )) || PCC goal create --title "$GOAL_TITLE" --level company --status active \
                 --description "$(cat "$AG/company-mission.md")" >/dev/null
fi

# --------------------------------------------------------------- 5. agents ---
# Org chart = the ladder: CEO -> Chief Architect -> Principal Engineer -> pyro/webby/ops;
# Reviewer and Watchdog report to the CEO. Managers are created before their reports so
# the reportsTo placeholders resolve. (Reporting lines are the chart and the escalation
# path in Paperclip's eyes; who may assign to whom is set by permissions, not by this.)
ARCHITECT_ID=""; PRINCIPAL_ID=""
ARCHITECT_ID="$(upsert_agent "$AG/chief-architect" | tail -1)"
PRINCIPAL_ID="$(upsert_agent "$AG/principal-engineer" | tail -1)"
for d in reviewer watchdog pyro webby ops pixel; do
  upsert_agent "$AG/$d" >/dev/null
done

# --------------------------------------------------------------- 6. budget ---
# Since v2026.1023 any budget policy BLOCKS unpriced (local-model) usage unless told
# otherwise. Warn-only policy, hard stop off, unpriced allowed.
say "Company budget: warn at 80% of \$20/month, never hard-stop, local models allowed"
(( DRY )) || PCC budget policy:upsert --payload-json "$(jq -n --arg id "$COMPANY_ID" \
  '{scopeType:"company", scopeId:$id, amount:2000, warnPercent:80, hardStopEnabled:false, unpricedUsagePolicy:"allow", notifyEnabled:true, isActive:true}')" >/dev/null \
  || echo "   (budget policy upsert failed; set it in Company -> Costs -> Budgets: allow unpriced usage)"

# ------------------------------------------------------- 7. "ops" project ----
OPS_PROJECT_ID="$(PCC project list --json | jq -r '[.[] | select(.name=="ops")][0].id // empty')"
if [[ -z "$OPS_PROJECT_ID" ]]; then
  say "Creating project 'ops' (this repo's clone; home of the routines)"
  if (( ! DRY )); then
    OPS_PROJECT_ID="$(PCC project create --name ops --description "Company operations: QA sweeps, standups, mirrors. Codebase = devco-infra clone." \
        --execution-workspace-policy-json '{"enabled":true,"defaultMode":"shared_workspace","sharedWorkspaceConcurrency":"serialize"}' --json | jq -r .id)"
    PC project-workspace create "$OPS_PROJECT_ID" --payload-json "$(jq -n --arg cwd "$HOME/devco-infra" \
        '{name:"devco-infra", sourceType:"local_path", cwd:$cwd, defaultRef:"main"}')" >/dev/null
  fi
fi

# ------------------------------------------------------------- 8. routines ---
TZ_NAME="$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)"
WATCHDOG_ID="$(agent_id_by_name Watchdog)"; OPS_ID="$(agent_id_by_name ops)"
mk_routine() {  # mk_routine <title> <assignee-id> <cron> <description-file>
  local title="$1" who="$2" cron="$3" body="$4" rid tid tz
  rid="$(PCC routine list --json 2>/dev/null | jq -r --arg t "$title" '[.[] | select(.title==$t)][0].id // empty')"
  if [[ -n "$rid" ]]; then
    # Exists: make sure its schedule runs in the box's current time zone (the box may
    # have been on UTC when the routine was first created).
    (( DRY )) && { say "Routine exists: $title"; return 0; }
    PC routine get "$rid" --json | jq -r '.triggers[]? | select(.kind=="schedule") | "\(.id) \(.timezone)"' | while read -r tid tz; do
      [[ -n "$tid" && "$tz" != "$TZ_NAME" ]] || continue
      PC routine trigger:update "$tid" --payload-json "$(jq -n --arg z "$TZ_NAME" '{timezone:$z}')" >/dev/null && say "Routine exists: $title (schedule moved from $tz to $TZ_NAME)"
    done
    say "Routine exists: $title"; return 0
  fi
  say "Creating routine: $title  ($cron $TZ_NAME -> $who)"
  (( DRY )) && return 0
  rid="$(PCC routine create --payload-json "$(jq -n --arg t "$title" --arg a "$who" --arg p "$OPS_PROJECT_ID" --rawfile d "$body" \
          '{title:$t, assigneeAgentId:$a, projectId:$p, description:$d, priority:"low", concurrencyPolicy:"coalesce_if_active", catchUpPolicy:"skip_missed"}')" --json | jq -r .id)"
  PC routine trigger:create "$rid" --payload-json "$(jq -n --arg c "$cron" --arg z "$TZ_NAME" '{kind:"schedule", cronExpression:$c, timezone:$z}')" >/dev/null
}
if [[ -n "$WATCHDOG_ID" && -n "$OPS_ID" && -n "$OPS_PROJECT_ID" ]]; then
  mk_routine "Nightly QA sweep"      "$WATCHDOG_ID" "10 2 * * *"   "$HERE/routines/nightly-qa.md"
  mk_routine "Daily standup"         "$OPS_ID"      "40 7 * * 1-5" "$HERE/routines/standup.md"
  mk_routine "Weekly skills review"  "$OPS_ID"      "0 9 * * 0"    "$HERE/routines/skills-review.md"
else
  echo "   (skipping routines: watchdog/ops/project not resolved)"
fi

# ------------------------------------------------ 9. hire approval back ON ----
say "Company setting: require board approval for new hires"
(( DRY )) || PC company update "$COMPANY_ID" --payload-json '{"requireBoardApprovalForNewAgents":true}' >/dev/null

# ------------------------------------------------------- 10. experimental ----
say "Instance setting: isolated workspaces available (off by default; per-task opt-in)"
(( DRY )) || PC instance settings:experimental:update --payload-json '{"enableIsolatedWorkspaces":true}' >/dev/null 2>&1 \
  || echo "   (could not set experimental settings; Settings -> Experimental -> Enable Isolated Workspaces)"

(( DRY )) && { echo; echo "(dry run: nothing was changed)"; exit 0; }

# ------------------------------------------- 11. harness verification ----------
# Paperclip verifies every new agent with a real "hello" run through its harness
# (command present, login valid, model reachable) and PAUSES it if that fails.
say "Waiting for Paperclip's harness checks (up to 3 minutes)"
for _ in $(seq 1 36); do
  pending="$(PCC agent list --json | jq -r '[.[] | select(.lifecycleState != null and (.lifecycleState | test("verifying|preparing|resuming")))] | length')"
  [[ "${pending:-0}" == "0" ]] && break
  sleep 5
done
PCC agent list --json | jq -r '.[] | "   \(.name): \(.status)\(if .lifecycleError then "  <- " + .lifecycleError else "" end)"'
BROKEN="$(PCC agent list --json | jq -r '.[] | select(.status=="paused" and .lifecycleError != null) | .name')"
if [[ -n "$BROKEN" ]]; then
  cat <<EOF

!! These agents failed their harness check and were paused by Paperclip:
$(sed 's/^/     /' <<<"$BROKEN")
   Usual causes, per harness: hermes_local -> profile missing or gateway down
   (04-hermes/create-profiles.sh --smoke); claude_local -> claude not logged in or
   too old (claude auth status, claude update); codex_local -> codex login
   --device-auth; pi_local -> gateway down or ~/.pi/agent/models.json missing.
   Fix the cause, then re-run this script (or: devco retry): Paperclip re-runs the check.
EOF
fi

cat <<EOF

=====================================================================
Company built. Check it:  http://$DEVCO_LAN_IP:3100
  Agents           CEO (Sonnet), Reviewer (Codex), Watchdog (Pi/local),
                   pyro, webby, ops (Hermes/local), pixel (Codex, design),
                   Principal (Opus, escalation),
                   Chief Architect (Fable, last resort)
  Routines         Nightly QA sweep 02:10, Daily standup 07:40 weekdays,
                   Weekly skills review Sun 09:00  (all $TZ_NAME, all local models)
  Costs            Company -> Costs shows the Claude and ChatGPT quota windows

Next:
  1. Bring in the first project:   /opt/devco/bin/clone-project.sh peel --python
  2. Give the CEO its first task in the UI (README Phase 5). Its first run may
     wait in Approvals as "CEO Strategy": approve it once.
  3. When you start coding interactively:  devco pause   (resume with devco resume)
=====================================================================
EOF
