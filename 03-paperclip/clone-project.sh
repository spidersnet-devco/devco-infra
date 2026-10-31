#!/usr/bin/env bash
# 03-paperclip/clone-project.sh
# Brings a project from the GitHub org onto this box so the agents can work on it.
#
#   bash 03-paperclip/clone-project.sh peel
#   bash 03-paperclip/clone-project.sh peel --python     # also builds its .venv
#
# Clones via SSH as the bot into $DEVCO_REPOS/<name>, drops an AGENTS.md stub if
# the repo has none, runs a first QA pass so you know the baseline, and prints
# what to click in Paperclip to register it as a Project.
set -euo pipefail
source /opt/devco/devco.env

NAME="${1:?usage: clone-project.sh <repo-name> [--python|--node]}"
KIND="${2:-}"
DEST="$DEVCO_REPOS/$NAME"
URL="git@github.com:$GITHUB_ORG/$NAME.git"

mkdir -p "$DEVCO_REPOS"
if [[ -d "$DEST/.git" ]]; then
  echo "==> $DEST exists; pulling main"
  git -C "$DEST" checkout -q main && git -C "$DEST" pull -q --ff-only
else
  echo "==> Cloning $URL"
  git clone -q "$URL" "$DEST"
fi
cd "$DEST"

if [[ ! -f AGENTS.md && ! -f CLAUDE.md ]]; then
  echo "==> No AGENTS.md; writing a stub for the agents to fill in on their first ticket"
  cat > AGENTS.md <<EOF
# $NAME — notes for agents

<!-- The first engineer to work here fills this in and commits it with their PR. -->

## What this is
(one paragraph)

## How to run it
\`\`\`
# command(s)
\`\`\`

## How to test it
\`\`\`
/opt/devco/qa-run.sh $DEST
\`\`\`

## Layout
(top-level folders and what lives where)

## Do not touch
(generated files, vendored code, anything the board owns)
EOF
  git add AGENTS.md
  git commit -qm "chore: add AGENTS.md stub for agents" || true
  git push -q || echo "   (push failed: bot may not have Write on $NAME yet; see agents/github-access.md)"
fi

case "$KIND" in
  --python)
    echo "==> Python venv"
    python3 -m venv .venv
    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install -q -U pip
    [[ -f requirements.txt ]] && pip install -q -r requirements.txt
    [[ -f pyproject.toml ]] && (pip install -q -e ".[dev]" 2>/dev/null || pip install -q -e . || true)
    deactivate
    ;;
  --node)
    echo "==> npm install"
    npm ci >/dev/null 2>&1 || npm install >/dev/null 2>&1 || true
    ;;
esac

echo "==> Baseline QA (so the first ticket's PASS/FAIL means something)"
/opt/devco/qa-run.sh "$DEST" 2>&1 | tail -n 15 || true

cat <<EOF

=====================================================================
$NAME is at $DEST (branch main, remote = bot SSH).

Register it in Paperclip:
  Projects -> New project
    Name:        $NAME
    Repository:  $URL
    Workspace:   $DEST
    Enable "isolated execution workspaces" (git worktrees) if offered,
    so parallel tasks don't share one checkout.

Then the first ticket for this project goes to the CEO (see README Phase 6).
=====================================================================
EOF
