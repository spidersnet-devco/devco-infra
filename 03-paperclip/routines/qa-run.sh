#!/usr/bin/env bash
# /opt/devco/qa-run.sh — the QA "agent" that is not an LLM.
# Runs lint + tests for a repo and prints a compact, machine-readable summary.
# Every engineer skill calls this before handing back; the Watchdog re-runs it.
#
#   qa-run.sh /opt/devco/repos/peel [branch]
set -uo pipefail

REPO="${1:?usage: qa-run.sh <repo-path> [branch]}"
BRANCH="${2:-}"
cd "$REPO" || { echo "QA: repo not found: $REPO"; exit 2; }

if [[ -n "$BRANCH" ]]; then
  git fetch -q origin "$BRANCH" 2>/dev/null || true
  git checkout -q "$BRANCH" || { echo "QA: cannot checkout $BRANCH"; exit 2; }
fi

STATUS=0
section() { echo; echo "=== $1 ==="; }

# ---- Python -----------------------------------------------------------------
if [[ -f pyproject.toml || -f requirements.txt || -f setup.py ]]; then
  section "python: environment"
  if [[ ! -d .venv ]]; then python3 -m venv .venv; fi
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install -q -U pip >/dev/null 2>&1 || true
  if [[ -f requirements.txt ]]; then pip install -q -r requirements.txt || STATUS=1; fi
  if [[ -f requirements-dev.txt ]]; then pip install -q -r requirements-dev.txt || STATUS=1; fi
  if [[ -f pyproject.toml ]]; then pip install -q -e ".[dev]" 2>/dev/null || pip install -q -e . 2>/dev/null || true; fi
  pip install -q ruff pytest >/dev/null 2>&1 || true

  section "python: ruff"
  ruff check . 2>&1 | tail -n 40 || STATUS=1
  [[ "${PIPESTATUS[0]}" -eq 0 ]] || STATUS=1

  section "python: pytest"
  # Qt apps need an offscreen platform when there is no display.
  QT_QPA_PLATFORM=offscreen pytest -q -x --maxfail=5 2>&1 | tail -n 60
  [[ "${PIPESTATUS[0]}" -eq 0 ]] || STATUS=1
fi

# ---- Node / web -------------------------------------------------------------
if [[ -f package.json ]]; then
  section "node: install"
  if [[ -f pnpm-lock.yaml ]]; then pnpm install --frozen-lockfile >/dev/null 2>&1 || STATUS=1
  else npm ci >/dev/null 2>&1 || npm install >/dev/null 2>&1 || STATUS=1; fi
  section "node: lint/test/build (whatever scripts exist)"
  for s in lint test build; do
    if jq -e ".scripts.\"$s\"" package.json >/dev/null 2>&1; then
      echo "--- npm run $s"
      npm run -s "$s" 2>&1 | tail -n 40
      [[ "${PIPESTATUS[0]}" -eq 0 ]] || STATUS=1
    fi
  done
fi

# ---- Single-file HTML apps --------------------------------------------------
if ls ./*.html >/dev/null 2>&1 && [[ ! -f package.json ]]; then
  section "html: basic validity"
  for f in ./*.html; do
    python3 - "$f" <<'PY' || STATUS=1
import sys, html.parser
class P(html.parser.HTMLParser):
    def __init__(s): super().__init__(); s.stack=[]
p=P(); p.feed(open(sys.argv[1],encoding="utf-8",errors="replace").read())
print("parsed:", sys.argv[1])
PY
  done
fi

# ---- Docker / compose -------------------------------------------------------
if ls docker-compose*.yml compose*.yml >/dev/null 2>&1; then
  section "compose: config validation"
  for f in docker-compose*.yml compose*.yml; do
    [[ -f "$f" ]] || continue
    docker compose -f "$f" config -q 2>&1 | tail -n 20
    [[ "${PIPESTATUS[0]}" -eq 0 ]] || STATUS=1
  done
fi

# ---- Shell ------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1 && ls ./*.sh >/dev/null 2>&1; then
  section "shellcheck"
  shellcheck ./*.sh 2>&1 | tail -n 40 || STATUS=1
fi

section "QA RESULT"
if [[ $STATUS -eq 0 ]]; then echo "QA: PASS ($REPO ${BRANCH:-HEAD})"; else echo "QA: FAIL ($REPO ${BRANCH:-HEAD})"; fi
exit $STATUS
