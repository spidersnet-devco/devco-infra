#!/usr/bin/env bash
# /opt/devco/bin/new-project.sh — a project from nothing, in one command.
#
#   new-project.sh <name> [--python|--node|--stacks] [--public] [--description "..."]
#
# What it does, as the bot (gh must be logged in as it: logins.sh step 3):
#   1. creates the GitHub repo <org>/<name> (private unless --public), with a README so
#      main exists;
#   2. gives the org team "agents" (GITHUB_TEAM) Write on it;
#   3. clones it to $DEVCO_REPOS/<name> and commits the agents' AGENTS.md and a
#      .gitignore for the stack straight onto main — a brand-new repo has nothing to
#      review yet, so no bootstrap PR;
#   4. hands over to clone-project.sh for the venv/npm install, the review labels, the
#      baseline QA and the Paperclip project + workspace.
# Re-running is safe: every step skips what already exists. The CEO may run this when
# the board's task names a project that does not exist yet (ceo/AGENTS.md).
set -euo pipefail
source /opt/devco/devco.env
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/opt/devco/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$HERE/templates"; [[ -d "$TPL" ]] || TPL="$HOME/devco-infra/03-paperclip/templates"
TEAM="${GITHUB_TEAM:-agents}"
die() { echo "!! $*" >&2; exit 1; }

NAME="${1:-}"; shift || true
[[ -n "$NAME" ]] || die "usage: new-project.sh <name> [--python|--node|--stacks] [--public] [--description \"...\"]"
[[ "$NAME" =~ ^[a-z0-9][a-z0-9._-]{0,99}$ ]] || die "project name must be lowercase letters, digits, '.', '_' or '-': $NAME"
KIND=""; VIS="--private"; DESC=""; REGISTER=1
while (( $# )); do
  case "$1" in
    --python|--node|--stacks) KIND="$1" ;;
    --public) VIS="--public" ;;
    --description) DESC="${2:-}"; shift ;;
    --no-register) REGISTER=0 ;;   # tests: stop before clone-project.sh
    *) die "unknown option $1" ;;
  esac
  shift
done

gh auth status >/dev/null 2>&1 || die "gh is not logged in as the bot (run 03-paperclip/logins.sh, step 3)"
BOT="$(gh api user -q .login 2>/dev/null || echo '?')"

if gh repo view "$GITHUB_ORG/$NAME" --json name >/dev/null 2>&1; then
  echo "==> Repo $GITHUB_ORG/$NAME exists; leaving it alone"
else
  echo "==> Creating $GITHUB_ORG/$NAME (${VIS#--}) as $BOT"
  args=(--add-readme "$VIS"); [[ -n "$DESC" ]] && args+=(--description "$DESC")
  gh repo create "$GITHUB_ORG/$NAME" "${args[@]}" >/dev/null \
    || die "could not create the repo. The org must let members create repositories (org Settings -> Member privileges -> Repository creation); otherwise create it in the browser with a README and re-run this."
fi

echo "==> Team '$TEAM' -> Write on $NAME"
# Needs admin on the repo (the creator has it) and membership of the team (the bot is in it).
if ! gh api -X PUT "/orgs/$GITHUB_ORG/teams/$TEAM/repos/$GITHUB_ORG/$NAME" -f permission=push >/dev/null 2>&1; then
  echo "   (could not add the team; if the repo was created in the browser, add '$TEAM' with Write under Settings -> Collaborators and teams)"
fi

DEST="$DEVCO_REPOS/$NAME"
mkdir -p "$DEVCO_REPOS"
if [[ ! -d "$DEST/.git" ]]; then
  echo "==> Cloning to $DEST"
  for _ in 1 2 3 4 5; do git clone -q "git@github.com:$GITHUB_ORG/$NAME.git" "$DEST" 2>/dev/null && break; sleep 3; done
  [[ -d "$DEST/.git" ]] || die "clone failed (is the bot's SSH key on GitHub and does '$TEAM' have Write?)"
fi
cd "$DEST"
git checkout -q main 2>/dev/null || git checkout -q -b main

echo "==> Bootstrap files on main (AGENTS.md, .gitignore)"
added=0
if [[ ! -s AGENTS.md && ! -s CLAUDE.md ]]; then       # -s: an empty file from a failed earlier run does not count
  sed "s/__NAME__/$NAME/g" "$TPL/AGENTS.md.template" > AGENTS.md; git add AGENTS.md; added=1
fi
if [[ ! -s .gitignore ]]; then
  case "$KIND" in
    --python) cp "$TPL/gitignore-python" .gitignore ;;
    --node)   cp "$TPL/gitignore-web"    .gitignore ;;
    --stacks) cp "$TPL/gitignore-stacks" .gitignore ;;
  esac
  [[ -f .gitignore ]] && { git add .gitignore; added=1; }
fi
if (( added )); then
  git -c user.name="${GITHUB_BOT_USER:-devco-bot}" -c user.email="${GITHUB_BOT_NOREPLY:-devco-bot@users.noreply.github.com}" \
      commit -qm "chore: repo bootstrap for the agents (AGENTS.md, .gitignore)"
  # The global pre-push hook refuses main; this is the one sanctioned exception (nothing to review yet).
  DEVCO_ALLOW_MAIN=1 git push -q origin main
  echo "   pushed to main"
else
  echo "   already there"
fi

(( REGISTER )) || { echo "==> --no-register: stopping before clone-project.sh"; exit 0; }
echo "==> Registering with the company"
exec /opt/devco/bin/clone-project.sh "$NAME" ${KIND:+"$KIND"}
