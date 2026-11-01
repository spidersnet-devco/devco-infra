#!/usr/bin/env bash
# tests/run-tests.sh — everything that can be checked without the real box.
#
#   bash tests/run-tests.sh            # all checks
#   bash tests/run-tests.sh --quick    # skip the qa-run.sh fixtures (no pip/venv)
#
# Checks: bash syntax + shellcheck, YAML/JSON parse, the autoinstall file against
# subiquity's schema (placeholders filled, nothing left over), the create-company.sh
# payload rendering, and qa-run.sh against small fixture repos (pass/fail cases).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUICK=0; [[ "${1:-}" == "--quick" ]] && QUICK=1
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $*"; }
check(){ local label="$1"; shift; if "$@" >/tmp/devco-test.out 2>&1; then ok "$label"; else bad "$label"; sed 's/^/       /' /tmp/devco-test.out | head -20; fi; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "== bash syntax"
mapfile -t SCRIPTS < <(cd "$ROOT" && git ls-files '*.sh' 'bin/*' 2>/dev/null || find "$ROOT" -name '*.sh' -not -path '*/.git/*')
for f in "${SCRIPTS[@]}"; do
  head -1 "$ROOT/$f" | grep -q 'bash' || continue
  check "bash -n $f" bash -n "$ROOT/$f"
done

echo "== shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  for f in "${SCRIPTS[@]}"; do
    head -1 "$ROOT/$f" | grep -q 'bash' || continue
    # SC1091: sourced devco.env is not in the repo. SC2154/SC1010: trap false positives.
    check "shellcheck $f" shellcheck -S warning -e SC1091 "$ROOT/$f"
  done
else echo "  skip (shellcheck not installed)"; fi

echo "== YAML / JSON"
for f in 02-models/llama-swap.yaml 04-hermes/config.template.yaml; do
  check "yaml $f" python3 -I -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$ROOT/$f"
done
for f in $(cd "$ROOT" && find . -name '*.json' -not -path './.git/*'); do
  check "json $f" python3 -I -m json.tool "$ROOT/$f" /dev/null
done
check "llama-swap.yaml has both role models + preload" python3 -I - "$ROOT/02-models/llama-swap.yaml" <<'PY'
import sys, yaml
c = yaml.safe_load(open(sys.argv[1]))
assert set(c["hooks"]["on_startup"]["preload"]) == {"coder-accurate", "coder-fast"}
for m in ("coder-accurate", "coder-fast"):
    cmd = c["models"][m]["cmd"]
    assert "--no-mmap" not in cmd and "${llama}" in cmd, m
assert "--load-mode none" in c["macros"]["llama"] and "-fa on" in c["macros"]["llama"]
assert c["routing"]["router"]["use"] == "group"
PY

echo "== autoinstall (00-unattended/user-data)"
UD="$WORK/user-data"
sed -e 's/__USERNAME__/geoff/g' -e 's#__SSH_PUBLIC_KEY__#ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl test#' \
    -e 's#__PASSWORD_HASH__#$6$rounds=5000$saltsalt$hashhashhashhashhashhashhashhashhashhashhashhashhashhashhashhashhashhashhashhashhashha#' \
    "$ROOT/00-unattended/user-data" > "$UD"
check "first line is #cloud-config" bash -c "head -1 '$UD' | grep -qx '#cloud-config'"
check "no placeholders left after fill" bash -c "! grep -q '__[A-Z_]*__' '$UD'"
check "user-data parses as YAML" python3 -I -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$UD"
check "service template tokens are all substituted" bash -c "sed 's/@@USER@@/geoff/g; s/@@UID@@/1000/g' '$ROOT/00-unattended/devco-bootstrap.service' | grep -qv '@@' && ! sed 's/@@USER@@/geoff/g; s/@@UID@@/1000/g' '$ROOT/00-unattended/devco-bootstrap.service' | grep -q '@@'"
check "meta-data present (a 404 aborts the installer)" test -s "$ROOT/00-unattended/meta-data"
SCHEMA="${AUTOINSTALL_SCHEMA:-$WORK/autoinstall-schema.json}"
if [[ ! -s "$SCHEMA" ]]; then
  curl -fsSL -o "$SCHEMA" https://raw.githubusercontent.com/canonical/subiquity/26.04.1/autoinstall-schema.json 2>/dev/null || true
fi
if [[ -s "$SCHEMA" ]] && python3 -c 'import jsonschema' 2>/dev/null; then
  check "user-data validates against subiquity 26.04.1 schema" python3 -I - "$UD" "$SCHEMA" <<'PY'
import sys, yaml, json, jsonschema
doc = yaml.safe_load(open(sys.argv[1]))["autoinstall"]
jsonschema.validate(doc, json.load(open(sys.argv[2])))
PY
else echo "  skip (schema not fetched or jsonschema missing)"; fi

echo "== create-company.sh payload rendering"
for d in "$ROOT"/03-paperclip/agents/*/; do
  [[ -f "$d/agent.json" ]] || continue
  n="$(basename "$d")"
  check "agent $n: required keys + instruction files exist" python3 -I - "$d" <<'PY'
import sys, json, pathlib
d = pathlib.Path(sys.argv[1]); a = json.load(open(d / "agent.json"))
for k in ("name", "adapterType", "adapterConfig", "runtimeConfig", "permissions", "instructions", "paused"):
    assert k in a, f"missing {k}"
for f in a["instructions"]:
    assert (d / f).is_file(), f"missing {f}"
hb = a["runtimeConfig"]["heartbeat"]
assert hb["enabled"] is False and hb["wakeOnDemand"] is True and hb["maxConcurrentRuns"] == 1
if a["adapterType"] == "claude_local":
    assert a["adapterConfig"]["model"].startswith("claude-"), "full model id required"
if a["adapterType"] == "hermes_local":
    assert a["adapterConfig"]["env"]["HERMES_HOME"].endswith(d.name), "HERMES_HOME must point at the profile"
    assert a["adapterConfig"]["model"] == "coder-accurate"
    assert a["adapterConfig"]["hermesCommand"] == "/opt/devco/bin/hermes-run", "juniors run hermes through the wrapper"
if d.name == "watchdog":
    assert a["adapterConfig"].get("extraArgs") == ["--exclude-tools", "edit,write"], "the Watchdog must not be able to edit"
if d.name in ("principal-engineer", "chief-architect"):
    # Reachable by the CEO up the ladder (board decision 2026-10-31); not paused, not protected.
    assert "authorizationPolicy" not in a["permissions"] and a["paused"] is False
if d.name == "ceo":
    assert "--disallowedTools" in a["adapterConfig"].get("extraArgs", []), "CEO must have no editor"
PY
  # the same jq the script uses, with placeholders filled
  check "agent $n: rendered payload is valid JSON with a bundle" bash -c "
    base=\$(sed -e 's|__HOME__|/home/geoff|g' -e 's|__REPOS__|/opt/devco/repos|g' -e 's|__GATEWAY__|http://127.0.0.1:8080/v1|g' -e 's|__CEO_ID__|00000000-0000-4000-8000-000000000000|g' -e 's|__ARCHITECT_ID__|00000000-0000-4000-8000-000000000000|g' -e 's|__PRINCIPAL_ID__|00000000-0000-4000-8000-000000000000|g' '$d/agent.json')
    ! grep -q '__[A-Z_]*__' <<<\"\$base\" || { echo 'unfilled placeholder'; exit 1; }
    files='{}'; for k in \$(jq -r '.instructions[]' <<<\"\$base\"); do files=\$(jq --arg k \"\$k\" --rawfile v '$d'/\"\$k\" '. + {(\$k): \$v}' <<<\"\$files\"); done
    jq -e --argjson files \"\$files\" 'del(.instructions, .paused) | . + {instructionsBundle: {entryFile: \"AGENTS.md\", files: \$files}} | .instructionsBundle.files[\"AGENTS.md\"] | length > 100' <<<\"\$base\" >/dev/null"
done
check "org chart: CEO > Architect > Principal > juniors; QA under the CEO" bash -c "
  jq -e '.reportsTo==\"__CEO_ID__\"' '$ROOT/03-paperclip/agents/chief-architect/agent.json' >/dev/null &&
  jq -e '.reportsTo==\"__ARCHITECT_ID__\"' '$ROOT/03-paperclip/agents/principal-engineer/agent.json' >/dev/null &&
  for j in pyro webby ops pixel; do jq -e '.reportsTo==\"__PRINCIPAL_ID__\"' \"$ROOT/03-paperclip/agents/\$j/agent.json\" >/dev/null || exit 1; done &&
  for j in reviewer watchdog; do jq -e '.reportsTo==\"__CEO_ID__\"' \"$ROOT/03-paperclip/agents/\$j/agent.json\" >/dev/null || exit 1; done &&
  grep -q 'upsert_agent \"\$AG/chief-architect\"' '$ROOT/03-paperclip/create-company.sh' && grep -q 'ARCHITECT_ID=\"\$(upsert_agent' '$ROOT/03-paperclip/create-company.sh'"
check "hermes profiles run their own short-lived gateway (per-run PAPERCLIP_* env)" python3 -I -c '
import sys, yaml; c = yaml.safe_load(open(sys.argv[1]))
g = c["gateway"]; assert g["standalone"] is True and 0 < g["unmanaged_idle_exit_seconds"] <= 30' "$ROOT/04-hermes/config.template.yaml"
check "create-profiles.sh keeps gateway settings out of the default profile" grep -q 'over.pop("gateway", None)' "$ROOT/04-hermes/create-profiles.sh"
check "CEO model is Sonnet" bash -c "jq -e '.adapterConfig.model==\"claude-sonnet-5-5\"' '$ROOT/03-paperclip/agents/ceo/agent.json' >/dev/null"
check "skill descriptions <= 60 chars" bash -c "! grep -rh '^description:' '$ROOT'/04-hermes/profiles/*/skills/*/SKILL.md '$ROOT'/04-hermes/profiles/shared-skills/*/SKILL.md | awk -F'description: ' 'length(\$2)>60{f=1} END{exit !f}'"
check "no stale /opt/devco/qa-run.sh paths" bash -c "! grep -rn '/opt/devco/qa-run\.sh' '$ROOT' --include='*.md' --include='*.sh' --include='*.json' | grep -v 'bin/qa-run.sh'"
check "no hermes gateway/invite leftovers" bash -c "! grep -rln 'gateway install\|hermes_gateway\|8642' '$ROOT' --include='*.sh' --include='*.md' --include='*.yaml' --include='*.json' | grep -v 'NOTES.md\|03-paperclip/agents/README.md\|SECRETS.md\|tests/run-tests.sh'"

echo "== review-verdict.sh (fake gh + curl)"
FB="$WORK/fakebin"; mkdir -p "$FB"
cat > "$FB/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
[[ "$*" == *"--remove-label"* ]] && exit 1   # label not present: gh errors, the script must not care
exit 0
EOF
cat > "$FB/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$FAKE_LOG"; exit 0
EOF
chmod +x "$FB"/*; printf 'Looks good.\n1. yes\n' > "$WORK/body.md"; export FAKE_LOG="$WORK/verdict.log"; : > "$FAKE_LOG"
RV="$ROOT/03-paperclip/routines/review-verdict.sh"; PR=https://github.com/spidersnet-devco/peel/pull/2
check "approve: comment, label, Paperclip PATCH status=done" bash -c "PATH='$FB:$PATH' PAPERCLIP_API_URL=http://x PAPERCLIP_API_KEY=k PAPERCLIP_TASK_ID=t1 PAPERCLIP_RUN_ID=r1 bash '$RV' approve $PR '$WORK/body.md' && grep -q -- '--comment --body-file' '$FAKE_LOG' && grep -q -- '--add-label reviewer-approved' '$FAKE_LOG' && grep -q 'PATCH http://x/api/issues/t1' '$FAKE_LOG' && grep -q '\"status\": \"done\"' '$FAKE_LOG'"
: > "$FAKE_LOG"
check "changes: label changes-requested, no Paperclip call without run vars" bash -c "PATH='$FB:$PATH' bash '$RV' changes $PR '$WORK/body.md' | grep -q 'record the verdict on the task yourself' && grep -q -- '--add-label changes-requested' '$FAKE_LOG' && ! grep -q curl '$FAKE_LOG'"
check "refuses a non-PR url and an empty body" bash -c "! PATH='$FB:$PATH' bash '$RV' approve https://example.com/x '$WORK/body.md' 2>/dev/null && : > '$WORK/empty.md' && ! PATH='$FB:$PATH' bash '$RV' approve $PR '$WORK/empty.md' 2>/dev/null"
check "install-paperclip.sh installs hermes-run" grep -q 'hermes-run.sh" *\/opt/devco/bin/hermes-run' "$ROOT/03-paperclip/install-paperclip.sh"
check "every agent is told GitHub needs no Paperclip connection" bash -c "for n in reviewer pixel ceo watchdog principal-engineer chief-architect; do grep -q 'never ask for a \"connection\"' \"$ROOT/03-paperclip/agents/\$n/AGENTS.md\" || exit 1; done; grep -q 'never search for or request a Paperclip' '$ROOT/04-hermes/profiles/shared-skills/devco-workflow/SKILL.md'"
check "install-paperclip.sh installs new-project.sh" grep -q 'new-project.sh" *\/opt/devco/bin/new-project.sh' "$ROOT/03-paperclip/install-paperclip.sh"
check "install-paperclip.sh installs review-verdict.sh" grep -q 'review-verdict.sh" /opt/devco/bin/review-verdict.sh' "$ROOT/03-paperclip/install-paperclip.sh"

echo "== new-project.sh (fake gh + a local bare repo standing in for GitHub)"
NP="$WORK/np"; mkdir -p "$NP/bin" "$NP/home" "$NP/repos" "$NP/origin"; ln -s "$ROOT/03-paperclip/templates" "$NP/templates"
git init -q --bare "$NP/origin/demo.git"
seed="$WORK/np-seed"; git init -q -b main "$seed"; echo "# demo" > "$seed/README.md"
git -C "$seed" -c user.name=t -c user.email=t@t add README.md; git -C "$seed" -c user.name=t -c user.email=t@t commit -qm init; git -C "$seed" push -q "$NP/origin/demo.git" main 2>/dev/null
printf '#!/usr/bin/env bash\necho "gh $*" >> "$FAKE_LOG"; case "$1 $2" in "api user") echo bot;; "repo view") exit 1;; esac; exit 0\n' > "$NP/bin/gh"; chmod +x "$NP/bin/gh"
printf 'GITHUB_ORG="spidersnet-devco"\nDEVCO_REPOS="%s/repos"\nGITHUB_BOT_USER="bot"\nGITHUB_BOT_NOREPLY="1+bot@users.noreply.github.com"\n' "$NP" > "$NP/devco.env"
sed "s|source /opt/devco/devco.env|source $NP/devco.env|" "$ROOT/03-paperclip/new-project.sh" > "$NP/new-project.sh"
HOME="$NP/home" git config --global url."$NP/origin/".insteadOf "git@github.com:spidersnet-devco/"
HOME="$NP/home" git config --global core.hooksPath /nonexistent
export FAKE_LOG="$NP/log"; : > "$FAKE_LOG"
check "new-project.sh: creates repo, adds team, pushes AGENTS.md + .gitignore to main" bash -c "
  HOME='$NP/home' PATH='$NP/bin:$PATH' bash '$NP/new-project.sh' demo --python --no-register >/dev/null 2>&1 &&
  grep -q 'repo create spidersnet-devco/demo --add-readme --private' '$FAKE_LOG' &&
  grep -q 'teams/agents/repos/spidersnet-devco/demo -f permission=push' '$FAKE_LOG' &&
  [ \"\$(git -C '$NP/origin/demo.git' ls-tree --name-only main | sort | tr '\\n' ' ')\" = '.gitignore AGENTS.md README.md ' ] &&
  grep -q demo '$NP/repos/demo/AGENTS.md'"
check "new-project.sh: second run changes nothing" bash -c "
  before=\$(git -C '$NP/origin/demo.git' rev-parse main);
  HOME='$NP/home' PATH='$NP/bin:$PATH' bash '$NP/new-project.sh' demo --python --no-register 2>&1 | grep -q 'already there' &&
  [ \"\$(git -C '$NP/origin/demo.git' rev-parse main)\" = \"\$before\" ]"
check "new-project.sh: refuses a bad name before touching gh" bash -c "
  : > '$FAKE_LOG'; ! HOME='$NP/home' PATH='$NP/bin:$PATH' bash '$NP/new-project.sh' 'Bad Name' >/dev/null 2>&1 && [ ! -s '$FAKE_LOG' ]"

if (( QUICK )); then echo; echo "quick mode: skipping qa-run.sh fixtures"; else
echo "== qa-run.sh fixtures"
QA="$ROOT/03-paperclip/routines/qa-run.sh"
export DEVCO_QA_CACHE="$WORK/qa-cache"
mkrepo() {  # mkrepo <name> -> path; a git repo with origin pointing at a local bare
  local p="$WORK/$1"; mkdir -p "$p"; git -C "$p" init -q -b main; git -C "$p" config user.email t@t; git -C "$p" config user.name t
  echo "$p"
}
# python PASS
P="$(mkrepo py-pass)"; mkdir -p "$P/tests"
printf '[project]\nname="fx"\nversion="0.1"\n[tool.ruff]\nline-length=100\n' > "$P/pyproject.toml"
printf 'def add(a, b):\n    return a + b\n' > "$P/fx.py"
printf 'from fx import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n' > "$P/tests/test_fx.py"
git -C "$P" add -A && git -C "$P" commit -qm init
check "python repo with passing test -> PASS" bash -c "bash '$QA' '$P' | tail -1 | grep -q 'QA: PASS'"
# python FAIL (failing test)
F="$(mkrepo py-fail)"; cp -r "$P/." "$F/"; rm -rf "$F/.git"; git -C "$F" init -q -b main
printf 'def test_bad():\n    assert 1 == 2\n' > "$F/tests/test_fx.py"
check "python repo with failing test -> FAIL" bash -c "bash '$QA' '$F' | tail -1 | grep -q 'QA: FAIL'"
# python, no tests -> PASS with warning
N="$(mkrepo py-notests)"; printf '[project]\nname="n"\nversion="0.1"\n' > "$N/pyproject.toml"; printf 'x = 1\n' > "$N/n.py"
check "python repo with no tests -> PASS (warning, not failure)" bash -c "out=\$(bash '$QA' '$N'); grep -q 'WARN: no tests collected' <<<\"\$out\" && tail -1 <<<\"\$out\" | grep -q 'QA: PASS'"
# ruff failure in a repo WITHOUT ruff config -> warning only
R="$(mkrepo py-lintdebt)"; printf '[project]\nname="r"\nversion="0.1"\n' > "$R/pyproject.toml"; printf 'import os\nx = 1\n' > "$R/r.py"
check "unused import, no ruff config -> PASS with warning" bash -c "out=\$(bash '$QA' '$R'); grep -q 'WARN: ruff' <<<\"\$out\" && tail -1 <<<\"\$out\" | grep -q 'QA: PASS'"
# html good / bad
H="$(mkrepo html-ok)"; printf '<!doctype html><html><head><title>t</title></head><body><p>hi<br>there</p><div><span>x</span></div></body></html>\n' > "$H/app.html"
check "balanced single-file HTML -> PASS" bash -c "bash '$QA' '$H' | tail -1 | grep -q 'QA: PASS'"
B="$(mkrepo html-bad)"; printf '<!doctype html><html><body><div><span>x</div></span><script>var a=1;\n</body></html>\n' > "$B/app.html"
check "unbalanced HTML -> FAIL" bash -c "bash '$QA' '$B' | tail -1 | grep -q 'QA: FAIL'"
# compose: one file, valid (nullglob regression) ; invalid
C="$(mkrepo compose-ok)"; printf 'services:\n  web:\n    image: nginx:alpine\n    ports: ["8080:80"]\n' > "$C/compose.yaml"
check "single compose.yaml is detected and valid -> PASS" bash -c "out=\$(bash '$QA' '$C'); grep -q '=== compose' <<<\"\$out\" && tail -1 <<<\"\$out\" | grep -q 'QA: PASS'"
X="$(mkrepo compose-bad)"; printf 'services: [\n' > "$X/docker-compose.yml"
check "broken compose file -> FAIL" bash -c "bash '$QA' '$X' | tail -1 | grep -q 'QA: FAIL'"
# shell with a warning
S="$(mkrepo sh-warn)"; printf '#!/usr/bin/env bash\nfor f in $(ls); do echo "$f"; done\n' > "$S/run.sh"
if command -v shellcheck >/dev/null; then check "shellcheck warning -> FAIL" bash -c "bash '$QA' '$S' | tail -1 | grep -q 'QA: FAIL'"; fi
# branch mode uses a worktree and leaves the checkout alone
W="$(mkrepo wt)"; BARE="$WORK/wt.git"; git init -q --bare -b main "$BARE"
printf '[project]\nname="w"\nversion="0.1"\n' > "$W/pyproject.toml"; mkdir -p "$W/tests"; printf 'def test_a():\n    assert True\n' > "$W/tests/test_a.py"
git -C "$W" add -A && git -C "$W" commit -qm init && git -C "$W" remote add origin "$BARE" && git -C "$W" push -q -u origin main
git -C "$W" checkout -q -b devco/T1-x && printf 'def test_b():\n    assert False\n' > "$W/tests/test_b.py" && git -C "$W" add -A && git -C "$W" commit -qm bad && git -C "$W" push -q -u origin devco/T1-x && git -C "$W" checkout -q main
check "branch mode: failing branch -> FAIL, main checkout untouched" bash -c "bash '$QA' '$W' devco/T1-x | tail -1 | grep -q 'QA: FAIL' && [ \"\$(git -C '$W' rev-parse --abbrev-ref HEAD)\" = main ] && [ -z \"\$(git -C '$W' worktree list | tail -n +2)\" ]"
# per-repo override
O="$(mkrepo override)"; printf '#!/usr/bin/env bash\necho custom; exit 0\n' > "$O/.devco-qa.sh"; chmod +x "$O/.devco-qa.sh"
check ".devco-qa.sh override is honoured" bash -c "out=\$(bash '$QA' '$O'); grep -q 'repo override' <<<\"\$out\" && tail -1 <<<\"\$out\" | grep -q 'QA: PASS'"
fi

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
