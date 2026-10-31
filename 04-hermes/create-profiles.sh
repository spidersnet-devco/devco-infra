#!/usr/bin/env bash
# 04-hermes/create-profiles.sh
# Creates one isolated Hermes profile per specialist (from devco.env), seeds its
# SOUL.md and skills, points it at the model gateway, enables its API server on
# its own port, and installs its gateway as a user service.
#
# Idempotent: re-run after editing SOUL/skills to re-seed (existing agent-authored
# skills are left alone; our seed skills are overwritten).
set -euo pipefail
source /opt/devco/devco.env
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"

command -v hermes >/dev/null || { echo "hermes not installed; run 04-hermes/install-hermes.sh"; exit 1; }
python3 -c "import yaml" 2>/dev/null || pip3 install --user pyyaml

merge_config() {  # merge_config <profile_dir> <template>
  python3 - "$1" "$2" "$MODEL_GATEWAY_URL" "$MODEL_GATEWAY_KEY" "$DEVCO_REPOS" <<'PY'
import sys, yaml, pathlib
pdir, tmpl, gw, gwkey, repos = sys.argv[1:6]
cfg_path = pathlib.Path(pdir) / "config.yaml"
base = yaml.safe_load(cfg_path.read_text()) if cfg_path.exists() else {}
base = base or {}
text = pathlib.Path(tmpl).read_text()
text = text.replace("__GATEWAY_KEY__", gwkey).replace("__GATEWAY__", gw).replace("__REPOS__", repos)
over = yaml.safe_load(text) or {}
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            merge(a[k], v)
        else:
            a[k] = v
    return a
merge(base, over)
cfg_path.write_text(yaml.safe_dump(base, sort_keys=False))
print(f"    merged -> {cfg_path}")
PY
}

for entry in "${HERMES_PROFILES[@]}"; do
  IFS=: read -r name port desc <<<"$entry"
  PDIR="$HOME/.hermes/profiles/$name"
  echo "==> Profile: $name (port $port)"

  if [[ ! -d "$PDIR" ]]; then
    hermes profile create "$name" --description "$desc"
  else
    echo "    exists, re-seeding"
  fi

  # Identity
  install -m 0644 "$HERE/profiles/$name/SOUL.md" "$PDIR/SOUL.md"

  # Seed skills: shared company skills + the specialist's own
  mkdir -p "$PDIR/skills/devco"
  cp -r "$HERE/profiles/shared-skills/." "$PDIR/skills/devco/"
  cp -r "$HERE/profiles/$name/skills/." "$PDIR/skills/devco/"

  # Model routing (merged into the seeded config.yaml)
  merge_config "$PDIR" "$HERE/config.template.yaml"

  # API server for Paperclip (hermes_gateway adapter) — one port per profile
  ENV="$PDIR/.env"; touch "$ENV"
  if ! grep -q '^API_SERVER_ENABLED=' "$ENV"; then
    KEY="$(openssl rand -hex 32)"
    cat >>"$ENV" <<EOF

# --- Paperclip integration (devco) ---
API_SERVER_ENABLED=true
API_SERVER_KEY=$KEY
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=$port
# Fill these in after the Paperclip invite is approved (see invite-hermes-juniors.md),
# then: hermes -p $name gateway restart
#PAPERCLIP_API_URL=$PAPERCLIP_URL
#PAPERCLIP_API_KEY=
#PAPERCLIP_AGENT_ID=
#PAPERCLIP_COMPANY_ID=
EOF
    echo "    API server enabled on 127.0.0.1:$port (key written to $ENV)"
  fi

  # Gateway as a managed service
  hermes -p "$name" gateway install >/dev/null 2>&1 || "$name" gateway install || true
  hermes -p "$name" gateway restart || "$name" gateway start || true
  hermes -p "$name" doctor || true
done

echo
echo "==> Listening ports (expect one per profile):"
ss -ltnp 2>/dev/null | grep -E ':(8642|8643|8644)\b' || echo "   (none yet — check: hermes -p <name> logs -f)"

cat <<'EOF'

Profiles created. Quick test of one:
  pyro chat
  > what model are you using, and what is your working directory?

Next: 03-paperclip/agents/hire-tickets/invite-hermes-juniors.md
EOF
