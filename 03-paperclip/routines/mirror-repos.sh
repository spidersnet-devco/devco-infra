#!/usr/bin/env bash
# /opt/devco/bin/mirror-repos.sh — nightly bare mirror of every org repo the bot
# can see, into $GIT_MIRROR_DIR (NAS share). GitHub is the source of truth; this
# is the off-GitHub copy. Restore any repo with:  git clone <mirror-dir>/<name>.git
set -euo pipefail
source /opt/devco/devco.env

[[ -n "${GIT_MIRROR_DIR:-}" ]] || { echo "GIT_MIRROR_DIR empty; skipping"; exit 0; }
mkdir -p "$GIT_MIRROR_DIR"

ok=0; fail=0
while read -r name; do
  [[ -n "$name" ]] || continue
  dest="$GIT_MIRROR_DIR/$name.git"
  if [[ -d "$dest" ]]; then
    if git -C "$dest" remote update --prune >/dev/null 2>&1; then ok=$((ok+1)); else echo "FAIL update $name"; fail=$((fail+1)); fi
  else
    if git clone -q --mirror "git@github.com:$GITHUB_ORG/$name.git" "$dest"; then ok=$((ok+1)); else echo "FAIL clone $name"; fail=$((fail+1)); fi
  fi
done < <(gh repo list "$GITHUB_ORG" --limit 200 --json name --jq '.[].name')

echo "mirror: $ok ok, $fail failed -> $GIT_MIRROR_DIR ($(date +%F))"
[[ $fail -eq 0 ]]
