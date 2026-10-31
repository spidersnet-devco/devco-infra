#!/usr/bin/env bash
# /opt/devco/bin/review-verdict.sh — the Reviewer's verdict, as one command.
#
#   review-verdict.sh approve <pr-url> <body-file>
#   review-verdict.sh changes <pr-url> <body-file>
#
# Does the three things a verdict consists of, in order, so none gets skipped:
#   1. posts the review on GitHub as a *comment* review (the Reviewer shares the bot's
#      identity with the engineers, and GitHub refuses approve/request-changes on your
#      own PR);
#   2. sets the label the board looks for (reviewer-approved / changes-requested) and
#      removes the other one;
#   3. records the same verdict on the Paperclip task the run is working on, when the
#      PAPERCLIP_* run variables are present: approve -> status done, changes -> status
#      in_progress (Paperclip then sends the task back to the engineer).
# The first ~400 characters of the body become the Paperclip comment; the full text is
# on the PR, where the board reads it.
set -euo pipefail
verdict="${1:?usage: review-verdict.sh approve|changes <pr-url> <body-file>}"
url="${2:?usage: review-verdict.sh approve|changes <pr-url> <body-file>}"
body="${3:?usage: review-verdict.sh approve|changes <pr-url> <body-file>}"
case "$verdict" in
  approve) add=reviewer-approved; del=changes-requested; status="done";        word="Approved" ;;
  changes) add=changes-requested; del=reviewer-approved; status=in_progress; word="Changes requested" ;;
  *) echo "!! verdict must be 'approve' or 'changes' (got '$verdict')" >&2; exit 2 ;;
esac
[[ -s "$body" ]] || { echo "!! review body file is missing or empty: $body" >&2; exit 2; }
[[ "$url" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+$ ]] || { echo "!! not a GitHub PR URL: $url" >&2; exit 2; }

gh pr review "$url" --comment --body-file "$body"
gh pr edit "$url" --add-label "$add" >/dev/null
gh pr edit "$url" --remove-label "$del" >/dev/null 2>&1 || true
echo "GitHub: review comment posted and label '$add' set on $url"

if [[ -n "${PAPERCLIP_API_URL:-}" && -n "${PAPERCLIP_API_KEY:-}" && -n "${PAPERCLIP_TASK_ID:-}" ]]; then
  summary="$(head -c 400 "$body" | tr '\n' ' ' | sed 's/  */ /g')"
  payload="$(jq -n --arg s "$status" --arg c "$word: $summary (full review on the PR: $url)" '{status:$s, comment:$c}')"
  if curl -fsS -X PATCH "$PAPERCLIP_API_URL/api/issues/$PAPERCLIP_TASK_ID" \
       -H "Authorization: Bearer $PAPERCLIP_API_KEY" -H "X-Paperclip-Run-Id: ${PAPERCLIP_RUN_ID:-}" \
       -H 'Content-Type: application/json' -d "$payload" >/dev/null; then
    echo "Paperclip: task $PAPERCLIP_TASK_ID -> $status"
  else
    echo "!! Paperclip update failed. Record the verdict on the task yourself: PATCH /api/issues/$PAPERCLIP_TASK_ID {\"status\":\"$status\",\"comment\":\"$word ...\"}"
    exit 3
  fi
else
  echo "(no PAPERCLIP_* run variables: record the verdict on the task yourself, status=$status)"
fi
