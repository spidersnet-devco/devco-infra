#!/usr/bin/env bash
# /opt/devco/bin/qa-run.sh — the QA "agent" that is not an LLM.
# Lint + tests + compose validation + shellcheck, with a PASS/FAIL verdict.
# Engineers run it before handing back; the Reviewer, the Watchdog and the nightly
# sweep re-run it. Branch/PR/all modes never touch the shared checkout: they fetch
# into a detached throwaway worktree and remove it afterwards.
#
#   qa-run.sh <repo-path>                 QA of the working tree as it is (engineers, inside their workspace)
#   qa-run.sh <repo-path> <branch>        QA of origin/<branch> in a throwaway worktree
#   qa-run.sh --pr <github-pr-url>        QA of a pull request's head in a throwaway worktree
#   qa-run.sh --all-main                  QA of origin/main for every repo under $DEVCO_REPOS; summary table
#
# Per-repo override: if the repo has an executable .devco-qa.sh, it is run instead of
# the auto-detected checks and its exit code is the verdict.
#
# Exit: 0 PASS, 1 FAIL, 2 usage/setup problem.
set -uo pipefail
source /opt/devco/devco.env 2>/dev/null || true
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
DEVCO_REPOS="${DEVCO_REPOS:-/opt/devco/repos}"
CACHE="${DEVCO_QA_CACHE:-/opt/devco/cache/qa}"
mkdir -p "$CACHE" 2>/dev/null || CACHE="$(mktemp -d)"

STATUS=0; WARNINGS=0
section() { echo; echo "=== $1 ==="; }
fail()    { STATUS=1; echo "FAIL: $*"; }
warn()    { WARNINGS=$((WARNINGS+1)); echo "WARN: $*"; }
run()     { # run <max-lines> <cmd...> ; prints the tail of the output, returns the command's rc
  local n="$1"; shift; local out rc
  out="$("$@" 2>&1)"; rc=$?
  [[ -n "$out" ]] && echo "$out" | tail -n "$n"
  return $rc
}

# ------------------------------------------------------------- the checks ----
qa_dir() {  # qa_dir <dir> <label> [base-ref]   -> sets STATUS
  local dir="$1" label="$2" base="${3:-}" name
  cd "$dir" || { echo "QA: cannot cd to $dir"; STATUS=1; return; }
  # repo name = the main checkout's folder, also from inside a throwaway worktree (stable venv cache key)
  name="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$PWD/.git")")")"
  echo "QA target: $label  ($(git rev-parse --short HEAD 2>/dev/null || echo no-git))"

  if [[ -x .devco-qa.sh ]]; then
    section "repo override: .devco-qa.sh"
    run 80 ./.devco-qa.sh || fail ".devco-qa.sh exited $?"
    return
  fi

  # ---- Python ---------------------------------------------------------------
  if [[ -f pyproject.toml || -f requirements.txt || -f setup.py ]]; then
    section "python: environment"
    local venv="$CACHE/venv-$name"
    [[ -d "$venv" ]] || python3 -m venv "$venv" || { fail "cannot create venv"; return; }
    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    run 5 pip install -q -U pip >/dev/null || true
    [[ -f requirements.txt ]]     && { run 20 pip install -q -r requirements.txt     || fail "requirements.txt install"; }
    [[ -f requirements-dev.txt ]] && { run 20 pip install -q -r requirements-dev.txt || fail "requirements-dev.txt install"; }
    if [[ -f pyproject.toml ]]; then
      run 20 pip install -q -e ".[dev]" >/dev/null 2>&1 || run 20 pip install -q -e . || warn "editable install failed (ok for script-only repos)"
    fi
    run 5 pip install -q ruff pytest >/dev/null || warn "could not install ruff/pytest (offline?)"
    echo "python $(python --version 2>&1 | cut -d' ' -f2), venv $venv"

    section "python: ruff"
    local files=() ruff_rc
    if [[ -n "$base" ]]; then
      mapfile -t files < <(git diff --name-only --diff-filter=AMR "$base"...HEAD -- '*.py' 2>/dev/null)
      echo "linting ${#files[@]} changed .py file(s) vs $base"
    fi
    if [[ -n "$base" && ${#files[@]} -eq 0 ]]; then
      echo "no Python files changed"
    elif [[ -n "$base" ]]; then
      run 40 ruff check "${files[@]}"; ruff_rc=$?
      (( ruff_rc == 0 )) || fail "ruff found problems in changed files"
    else
      run 40 ruff check .; ruff_rc=$?
      if (( ruff_rc != 0 )); then
        if grep -qE '^\[tool\.ruff' pyproject.toml 2>/dev/null || [[ -f ruff.toml || -f .ruff.toml ]]; then
          fail "ruff found problems (repo has a ruff config, so this is enforced)"
        else
          warn "ruff found problems; not enforced because the repo has no ruff config (pre-existing debt)"
        fi
      fi
    fi

    section "python: pytest"
    local prc
    QT_QPA_PLATFORM=offscreen run 60 timeout 1200 python -m pytest -q --maxfail=5 -p no:cacheprovider; prc=$?
    case $prc in
      0) echo "tests passed" ;;
      5) warn "no tests collected" ;;
      124) fail "pytest timed out after 20 minutes" ;;
      *) fail "pytest exited $prc" ;;
    esac
    deactivate 2>/dev/null || true
  fi

  # ---- Node / web -----------------------------------------------------------
  if [[ -f package.json ]]; then
    section "node: install"
    if [[ -f pnpm-lock.yaml ]] && command -v pnpm >/dev/null; then run 20 pnpm install --frozen-lockfile >/dev/null || fail "pnpm install"
    elif [[ -f package-lock.json ]]; then run 20 npm ci --no-audit --no-fund >/dev/null || fail "npm ci"
    else run 20 npm install --no-audit --no-fund >/dev/null || fail "npm install"; fi
    section "node: lint / test / build (whichever scripts exist)"
    local s found=0
    for s in lint test build; do
      if jq -e ".scripts.\"$s\"" package.json >/dev/null 2>&1; then
        found=1; echo "--- npm run $s"
        CI=1 run 40 timeout 1200 npm run -s "$s" || fail "npm run $s"
      fi
    done
    (( found )) || warn "package.json has no lint/test/build scripts"
  fi

  # ---- Single-file HTML apps --------------------------------------------------
  shopt -s nullglob
  local htmls=(./*.html)
  shopt -u nullglob
  if (( ${#htmls[@]} )) && [[ ! -f package.json ]]; then
    section "html: structure (${#htmls[@]} file(s))"
    local f
    for f in "${htmls[@]}"; do
      if ! python3 - "$f" <<'PY'
import sys, html.parser
VOID = {"area","base","br","col","embed","hr","img","input","link","meta","param","source","track","wbr"}
class P(html.parser.HTMLParser):
    def __init__(s): super().__init__(convert_charrefs=True); s.stack=[]; s.errors=[]
    def handle_starttag(s, t, a):
        if t not in VOID: s.stack.append((t, s.getpos()[0]))
    def handle_startendtag(s, t, a): pass
    def handle_endtag(s, t):
        if t in VOID: return
        if s.stack and s.stack[-1][0]==t: s.stack.pop(); return
        # tolerate implicitly closed p/li/td/tr/option like browsers do
        for i in range(len(s.stack)-1, -1, -1):
            if s.stack[i][0]==t:
                for extra,_ in s.stack[i+1:]:
                    if extra not in {"p","li","td","th","tr","option","dd","dt"}:
                        s.errors.append(f"line {s.getpos()[0]}: </{t}> closes an open <{extra}>")
                del s.stack[i:]; return
        s.errors.append(f"line {s.getpos()[0]}: stray </{t}>")
p=P(); src=open(sys.argv[1],encoding="utf-8",errors="replace").read(); p.feed(src); p.close()
for t,l in p.stack:
    if t not in {"html","body","head","p","li","td","th","tr","option","dd","dt"}: p.errors.append(f"line {l}: <{t}> never closed")
if "<script" in src.lower() and "</script>" not in src.lower(): p.errors.append("<script> never closed")
for e in p.errors[:20]: print("  ", e)
print(("FAIL" if p.errors else "ok"), sys.argv[1]); sys.exit(1 if p.errors else 0)
PY
      then fail "unbalanced HTML in $f"; fi
      if command -v tidy >/dev/null 2>&1; then
        tidy -qe "$f" >/dev/null 2>&1; local trc=$?
        (( trc == 2 )) && { run 15 tidy -qe "$f"; fail "tidy reports errors in $f"; }
      fi
    done
  fi

  # ---- Docker / compose -------------------------------------------------------
  shopt -s nullglob
  local composes=(compose*.y*ml docker-compose*.y*ml)
  shopt -u nullglob
  if (( ${#composes[@]} )); then
    section "compose: config validation (${#composes[@]} file(s))"
    local f
    for f in "${composes[@]}"; do
      if docker compose version >/dev/null 2>&1; then
        run 20 docker compose -f "$f" config -q --no-interpolate || fail "compose config invalid: $f"
      else
        python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert isinstance(d.get("services"),dict) and d["services"], "no services"' "$f" \
          && echo "yaml ok (docker compose unavailable, so only parsed): $f" \
          || fail "compose file does not parse: $f"
      fi
    done
  fi

  # ---- Shell ------------------------------------------------------------------
  local shs
  mapfile -t shs < <(find . -name '*.sh' -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.git/*' 2>/dev/null | head -200)
  if (( ${#shs[@]} )); then
    section "shellcheck (${#shs[@]} script(s))"
    if command -v shellcheck >/dev/null 2>&1; then
      run 40 shellcheck -S warning "${shs[@]}" || fail "shellcheck warnings/errors"
    else
      warn "shellcheck not installed"
    fi
  fi
}

# ------------------------------------------------------------ worktree QA ----
qa_ref() {  # qa_ref <repo-path> <fetch-spec> <label> [base]
  local repo="$1" spec="$2" label="$3" base="${4-origin/main}" wt rc sha     # "" = lint whole repo
  git -C "$repo" fetch -q origin main 2>/dev/null || true                     # base ref for changed-files lint
  git -C "$repo" fetch -q origin "$spec" || { echo "QA: cannot fetch $spec in $repo"; return 2; }
  sha="$(git -C "$repo" rev-parse FETCH_HEAD)"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/devco-qa.XXXXXX")"
  git -C "$repo" worktree add -q --detach "$wt" "$sha" || { echo "QA: worktree add failed"; rm -rf "$wt"; return 2; }
  ( qa_dir "$wt" "$label" "$base"; exit $STATUS ); rc=$?
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  return $rc
}

verdict() { # verdict <label> <rc>
  section "QA RESULT"
  if (( $2 == 0 )); then echo "QA: PASS ($1)"; else echo "QA: FAIL ($1)"; fi
}

# ------------------------------------------------------------------- main ----
case "${1:-}" in
  "" | -h | --help)
    sed -n '2,20p' "$0"; exit 2 ;;

  --pr)
    URL="${2:?usage: qa-run.sh --pr <github-pr-url>}"
    command -v gh >/dev/null || { echo "QA: gh not installed"; exit 2; }
    read -r REPO_NAME NUM BASE_REF < <(gh pr view "$URL" --json headRepository,number,baseRefName \
        --jq '[.headRepository.name, (.number|tostring), .baseRefName] | @tsv' | tr '\t' ' ') || { echo "QA: gh pr view failed"; exit 2; }
    REPO="$DEVCO_REPOS/$REPO_NAME"
    if [[ ! -d "$REPO/.git" ]]; then
      REPO="$(mktemp -d)/$REPO_NAME"
      git clone -q "git@github.com:${GITHUB_ORG:-spidersnet-devco}/$REPO_NAME.git" "$REPO" || { echo "QA: clone failed"; exit 2; }
    fi
    qa_ref "$REPO" "refs/pull/$NUM/head" "PR #$NUM of $REPO_NAME" "origin/${BASE_REF:-main}"; rc=$?
    verdict "PR #$NUM $REPO_NAME" $rc; exit $rc ;;

  --all-main)
    declare -A RESULTS=(); any=0
    for d in "$DEVCO_REPOS"/*/; do
      [[ -d "$d/.git" ]] || continue
      n="$(basename "$d")"; STATUS=0; WARNINGS=0
      echo; echo "################ $n (origin/main)"
      qa_ref "$d" main "$n origin/main" "" ; rc=$?
      RESULTS[$n]=$rc; (( rc == 0 )) || any=1
    done
    section "SUMMARY"
    for n in "${!RESULTS[@]}"; do printf '%-30s %s\n' "$n" "$([[ ${RESULTS[$n]} -eq 0 ]] && echo PASS || echo FAIL)"; done | sort
    echo "QA: $([[ $any -eq 0 ]] && echo PASS || echo FAIL) (${#RESULTS[@]} repos)"
    exit $any ;;

  *)
    REPO="$1"; BRANCH="${2:-}"
    [[ -d "$REPO" ]] || { echo "QA: repo not found: $REPO"; exit 2; }
    if [[ -n "$BRANCH" ]]; then
      qa_ref "$REPO" "$BRANCH" "$(basename "$REPO") $BRANCH" "origin/main"; rc=$?
      verdict "$(basename "$REPO") $BRANCH" $rc; exit $rc
    fi
    qa_dir "$REPO" "$(basename "$REPO") working tree"
    verdict "$(basename "$REPO") $(git -C "$REPO" symbolic-ref --short -q HEAD 2>/dev/null || echo HEAD)" $STATUS
    exit $STATUS ;;
esac
