#!/usr/bin/env bash
# /opt/devco/bin/clone-project.sh
# Brings a project from the GitHub org onto this box so the agents can work on it,
# and registers it in Paperclip as a Project with a codebase folder.
#
#   clone-project.sh peel                       # clone + register
#   clone-project.sh peel --python              # also build its venv (--node for npm install)
#   clone-project.sh peel --python --bootstrap-pr
#       also open a PR (never a push to main) adding AGENTS.md + .gitignore from the
#       templates, so the repo starts with the conventions the agents expect
#
# Needs: github-setup.sh done (SSH as the bot). Registering in Paperclip needs the
# CLI logged in (logins.sh step 5); otherwise it prints what to click.
set -euo pipefail
source /opt/devco/devco.env
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/opt/devco/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$HERE/templates"; [[ -d "$TPL" ]] || TPL="$HOME/devco-infra/03-paperclip/templates"
PC() { paperclipai "$@" --api-base "$PAPERCLIP_URL"; }   # --api-base is a per-command option, so it goes last

NAME="${1:?usage: clone-project.sh <repo-name> [--python|--node|--stacks] [--bootstrap-pr]}"; shift
KIND=""; BOOTSTRAP=0
for a in "$@"; do case "$a" in --python|--node|--stacks) KIND="$a" ;; --bootstrap-pr) BOOTSTRAP=1 ;; *) echo "unknown option $a"; exit 2 ;; esac; done
DEST="$DEVCO_REPOS/$NAME"
SSH_URL="git@github.com:$GITHUB_ORG/$NAME.git"
HTTPS_URL="https://github.com/$GITHUB_ORG/$NAME.git"      # what Paperclip wants (it rejects git@ URLs)

mkdir -p "$DEVCO_REPOS"
if [[ -d "$DEST/.git" ]]; then
  echo "==> $DEST exists; fetching"
  git -C "$DEST" fetch -q --prune origin
  if [[ -z "$(git -C "$DEST" status --porcelain)" && "$(git -C "$DEST" rev-parse --abbrev-ref HEAD)" == "main" ]]; then
    git -C "$DEST" pull -q --ff-only || echo "   (main not fast-forwardable; left as is)"
  else
    echo "   (working tree busy or not on main; left as is)"
  fi
else
  echo "==> Cloning $SSH_URL"
  git clone -q "$SSH_URL" "$DEST" || { echo "!! clone failed. Is the bot's SSH key added and does the 'agents' team have Write on $NAME? (agents/github-access.md)"; exit 1; }
fi
cd "$DEST"

case "$KIND" in
  --python)
    echo "==> Python venv"
    [[ -d .venv ]] || python3 -m venv .venv
    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install -q -U pip
    [[ -f requirements.txt ]] && pip install -q -r requirements.txt
    [[ -f pyproject.toml ]] && (pip install -q -e ".[dev]" 2>/dev/null || pip install -q -e . || true)
    deactivate
    ;;
  --node)
    echo "==> npm install"
    npm ci --no-audit --no-fund >/dev/null 2>&1 || npm install --no-audit --no-fund >/dev/null 2>&1 || true
    ;;
esac

echo "==> Review labels on GitHub (the Reviewer uses them; needs gh logged in as the bot)"
if gh auth status >/dev/null 2>&1; then
  gh label create reviewer-approved --repo "$GITHUB_ORG/$NAME" --color 0E8A16 --description "Reviewer verdict: ready for the board to merge" --force >/dev/null 2>&1 || echo "   (could not create label; bot may lack Write)"
  gh label create changes-requested --repo "$GITHUB_ORG/$NAME" --color D93F0B --description "Reviewer verdict: fix the numbered list" --force >/dev/null 2>&1 || true
else
  echo "   (gh not logged in yet; labels will be created when you re-run after logins.sh)"
fi

if (( BOOTSTRAP )); then
  echo "==> Bootstrap PR: AGENTS.md + .gitignore (a branch and a PR, never main)"
  BR="devco/repo-bootstrap"
  if [[ -n "$(git status --porcelain)" ]]; then echo "!! working tree is dirty; not creating the bootstrap branch"; else
    git checkout -q -B "$BR" origin/main
    added=0
    if [[ ! -f AGENTS.md && ! -f CLAUDE.md ]]; then
      sed "s/__NAME__/$NAME/g" "$TPL/AGENTS.md.template" > AGENTS.md; git add AGENTS.md; added=1
    fi
    if [[ ! -f .gitignore ]]; then
      case "$KIND" in --python) cp "$TPL/gitignore-python" .gitignore ;; --node) cp "$TPL/gitignore-web" .gitignore ;; --stacks) cp "$TPL/gitignore-stacks" .gitignore ;; *) ;; esac
      [[ -f .gitignore ]] && { git add .gitignore; added=1; }
    fi
    if (( added )); then
      git commit -qm "chore: add AGENTS.md and .gitignore for the agents"
      git push -q -u origin "$BR" && gh pr create --base main --head "$BR" --title "chore: repo bootstrap for the agents" \
        --body "Adds AGENTS.md (conventions for the AI engineers) and a .gitignore. Opened by clone-project.sh; nothing else changed." \
        --label reviewer-approved 2>/dev/null || gh pr create --base main --head "$BR" --title "chore: repo bootstrap for the agents" --body "Adds AGENTS.md and .gitignore. Opened by clone-project.sh." || echo "   (PR creation failed; branch $BR is pushed)"
    else
      echo "   nothing to add"
    fi
    git checkout -q main
  fi
fi

echo "==> Baseline QA on main (so the first ticket's PASS/FAIL means something)"
/opt/devco/bin/qa-run.sh "$DEST" 2>&1 | tail -n 12 || true

echo "==> Registering in Paperclip"
if command -v paperclipai >/dev/null && PC auth whoami --json >/dev/null 2>&1; then
  CID="$(PC company list --json | jq -r '.[0].id')"
  PID="$(PC project list --company-id "$CID" --json | jq -r --arg n "$NAME" '[.[] | select(.name==$n)][0].id // empty')"
  if [[ -z "$PID" ]]; then
    PID="$(PC project create --company-id "$CID" --name "$NAME" --status in_progress \
            --execution-workspace-policy-json '{"enabled":true,"defaultMode":"shared_workspace","sharedWorkspaceConcurrency":"serialize"}' --json | jq -r .id)"
    SETUP=""; [[ "$KIND" == "--python" ]] && SETUP='python3 -m venv .venv && .venv/bin/pip install -q -e ".[dev]" || .venv/bin/pip install -q -r requirements.txt || true'
    [[ "$KIND" == "--node" ]] && SETUP='npm ci --no-audit --no-fund || npm install'
    PC project-workspace create "$PID" --payload-json "$(jq -n --arg n "$NAME" --arg cwd "$DEST" --arg url "$HTTPS_URL" --arg s "$SETUP" \
      '{name:$n, sourceType:"local_path", cwd:$cwd, repoUrl:$url, defaultRef:"main"} + (if $s != "" then {setupCommand:$s} else {} end)')" >/dev/null
    echo "   project '$NAME' created with codebase $DEST (shared workspace, runs serialized)"
  else
    echo "   project '$NAME' already registered ($PID)"
  fi
else
  cat <<EOF
   Paperclip CLI not logged in; register by hand:
     Projects -> Add Project -> Name: $NAME
     then the project's Configuration: Source repos -> Existing repo URL: $HTTPS_URL
     Codebase -> Set local folder: $DEST
     Execution workspaces: shared workspace, concurrency "serialize"
EOF
fi

cat <<EOF

=====================================================================
$NAME is at $DEST (branch main, remote = bot SSH).
First ticket for this project goes to the CEO (README Phase 5). Remember: the
CEO must set the Project field on every ticket it creates for this repo.
=====================================================================
EOF
