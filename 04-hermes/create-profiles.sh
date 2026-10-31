#!/usr/bin/env bash
# 04-hermes/create-profiles.sh
# Creates one isolated Hermes profile per specialist (from HERMES_PROFILES in
# devco.env), seeds its SOUL.md, points its skills at this repo, and merges the
# model/gateway config. No API server, no gateway, no ports: Paperclip runs each
# profile itself (hermes_local adapter with HERMES_HOME=~/.hermes/profiles/<name>).
#
# Idempotent: re-run after editing SOUL/config. Skills need no re-seed (they are
# read from the repo clone). Agent-authored skills in the profile are left alone.
#
#   bash 04-hermes/create-profiles.sh            # create/update
#   bash 04-hermes/create-profiles.sh --smoke    # also run one quick question per profile through the gateway
set -euo pipefail
source /opt/devco/devco.env
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
SMOKE=0; [[ "${1:-}" == "--smoke" ]] && SMOKE=1

command -v hermes >/dev/null || { echo "hermes not installed; run 04-hermes/install-hermes.sh"; exit 1; }
python3 -c "import yaml" 2>/dev/null || { echo "python3-yaml missing (01-base/install-base.sh)"; exit 1; }

merge_config() {  # merge_config <profile_dir> <template> <name>   (name "default" = no profile skills)
  python3 - "$1" "$2" "$3" "$MODEL_GATEWAY_URL" "$MODEL_GATEWAY_KEY" "$DEVCO_REPOS" "$REPO_ROOT" <<'PY'
import sys, yaml, pathlib
pdir, tmpl, name, gw, gwkey, repos, repo = sys.argv[1:8]
cfg_path = pathlib.Path(pdir) / "config.yaml"
base = (yaml.safe_load(cfg_path.read_text()) if cfg_path.exists() else {}) or {}
text = pathlib.Path(tmpl).read_text()
for k, v in (("__GATEWAY_KEY__", gwkey), ("__GATEWAY__", gw), ("__REPOS__", repos), ("__REPO__", repo), ("__NAME__", name)):
    text = text.replace(k, v)
over = yaml.safe_load(text) or {}
if name == "default":
    over.pop("skills", None)          # the default profile has no specialist skills
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            merge(a[k], v)
        else:
            a[k] = v          # lists and scalars are replaced, not appended
    return a
merge(base, over)
cfg_path.write_text(yaml.safe_dump(base, sort_keys=False))
print(f"    merged -> {cfg_path}")
PY
}

# The DEFAULT profile (~/.hermes) gets the same model/gateway config, for two reasons:
#  - `hermes chat` with no profile works against the gateway (handy for you)
#  - Paperclip's harness check for hermes_local agents reads ~/.hermes/config.yaml
#    (not the profile's) to decide whether a model/API key is configured; without
#    this it reports "No LLM API keys found" and pauses every junior.
echo "==> Default profile: model + gateway config"
mkdir -p "$HOME/.hermes"
merge_config "$HOME/.hermes" "$HERE/config.template.yaml" default

for entry in "${HERMES_PROFILES[@]}"; do
  IFS=: read -r name desc <<<"$entry"
  PDIR="$HOME/.hermes/profiles/$name"
  echo "==> Profile: $name"
  [[ -d "$HERE/profiles/$name" ]] || { echo "!! no $HERE/profiles/$name folder in the repo"; exit 1; }

  if [[ ! -d "$PDIR" ]]; then
    hermes profile create "$name" --description "$desc"
  else
    echo "    exists, updating"
  fi
  mkdir -p "$PDIR/skills"

  # Identity
  install -m 0644 "$HERE/profiles/$name/SOUL.md" "$PDIR/SOUL.md"

  # Remove the old copied-skills folder from v1 of this script (skills now come from the repo)
  [[ -d "$PDIR/skills/devco" ]] && rm -rf "$PDIR/skills/devco" && echo "    removed stale copied skills (now read from the repo)"

  # Model routing, limits, skills dirs (merged into the seeded config.yaml)
  merge_config "$PDIR" "$HERE/config.template.yaml" "$name"

  # Leftovers from the per-profile API-server design: not needed with hermes_local
  if [[ -f "$PDIR/.env" ]] && grep -q '^API_SERVER_ENABLED=' "$PDIR/.env"; then
    sed -i '/^# --- Paperclip integration/,/^#PAPERCLIP_COMPANY_ID=/d; /^API_SERVER_/d' "$PDIR/.env"
    echo "    removed API_SERVER_* from $PDIR/.env (Paperclip runs this profile directly now)"
  fi

  # Doctor exits non-zero for two notes that are expected on this box and never go away:
  # the ".env has no API key" hint (the gateway is configured in config.yaml and needs no
  # key) and Hermes's own upstream npm-audit items. Report only whatever else it found.
  dout="$(HERMES_HOME="$PDIR" NO_COLOR=1 hermes doctor 2>&1 || true)"
  unexpected="$(printf '%s\n' "$dout" | sed -n 's/^ *[0-9][0-9]*\. //p' \
                | grep -vE "^Run 'hermes setup' to configure (missing )?API keys|npm vulnerabilit" || true)"
  if [[ -z "$unexpected" ]]; then
    echo "    doctor: ok (only the expected notes: .env API-key hint, upstream npm audit)"
  else
    echo "    doctor: reported issues (HERMES_HOME=$PDIR hermes doctor):"
    printf '%s\n' "$unexpected" | sed 's/^/      - /'
  fi
done

if (( SMOKE )); then
  echo
  echo "==> Smoke: one quick question per profile through the gateway (needs llama-swap up)"
  for entry in "${HERMES_PROFILES[@]}"; do
    IFS=: read -r name _ <<<"$entry"
    printf '    %-6s ' "$name"
    HERMES_HOME="$HOME/.hermes/profiles/$name" timeout 300 hermes chat -q "Reply with exactly: OK $name" -Q --yolo --source tool 2>/dev/null | tail -n 2 | tr '\n' ' ' || echo "(failed)"
    echo
  done
fi

cat <<EOF

Profiles ready: $(for e in "${HERMES_PROFILES[@]}"; do printf '%s ' "${e%%:*}"; done)
Each is run by Paperclip as a hermes_local agent (03-paperclip/create-company.sh).
Talk to one yourself:   HERMES_HOME=~/.hermes/profiles/pyro hermes chat      (or: pyro chat)
Skills live in the repo: $REPO_ROOT/04-hermes/profiles/
EOF
