#!/usr/bin/env bash
# /opt/devco/bin/mirror-repos.sh — nightly bare mirror of every org repo the bot
# can see, into $GIT_MIRROR_DIR (a mounted NAS share). GitHub is the source of
# truth; this is the off-GitHub copy. Restore any repo with:
#   git clone <mirror-dir>/<name>.git
# Exit 0 when every repo mirrored, 1 if any failed, 2 if the share isn't mounted
# or the repo list could not be fetched (so a silent empty run never looks green).
set -euo pipefail
source /opt/devco/devco.env
export PATH="$HOME/.local/bin:$PATH"

[[ -n "${GIT_MIRROR_DIR:-}" ]] || { echo "mirror: GIT_MIRROR_DIR empty in devco.env; skipping"; exit 0; }

# Refuse to "mirror" into an unmounted mount point (it would silently fill the root disk).
if [[ "${GIT_MIRROR_REQUIRE_MOUNT:-1}" == "1" ]]; then
  mp="$GIT_MIRROR_DIR"
  while [[ "$mp" != "/" && ! -d "$mp" ]]; do mp="$(dirname "$mp")"; done
  if ! mountpoint -q "$mp" && ! findmnt -T "$GIT_MIRROR_DIR" >/dev/null 2>&1; then
    echo "mirror: $GIT_MIRROR_DIR is not on a mounted share (set GIT_MIRROR_REQUIRE_MOUNT=0 to allow a local dir)"; exit 2
  fi
fi
mkdir -p "$GIT_MIRROR_DIR" || { echo "mirror: cannot create $GIT_MIRROR_DIR"; exit 2; }

repos="$(gh repo list "$GITHUB_ORG" --limit 200 --json name --jq '.[].name')" \
  || { echo "mirror: gh repo list failed (bot not logged in? run: gh auth status)"; exit 2; }
[[ -n "$repos" ]] || { echo "mirror: gh returned no repositories for $GITHUB_ORG"; exit 2; }

ok=0; fail=0
while read -r name; do
  [[ -n "$name" ]] || continue
  dest="$GIT_MIRROR_DIR/$name.git"
  if [[ -d "$dest" ]]; then
    if git -C "$dest" remote update --prune >/dev/null 2>&1; then ok=$((ok+1)); else echo "FAIL update $name"; fail=$((fail+1)); fi
  else
    if git clone -q --mirror "git@github.com:$GITHUB_ORG/$name.git" "$dest"; then ok=$((ok+1)); else echo "FAIL clone $name"; fail=$((fail+1)); fi
  fi
done <<<"$repos"

echo "mirror: $ok ok, $fail failed -> $GIT_MIRROR_DIR ($(date +%F))"
[[ $fail -eq 0 ]]
