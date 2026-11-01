#!/usr/bin/env bash
# /opt/devco/bin/lockdown.sh — run ONCE when the setup is done (README Phase 6).
#
# Until now your user has passwordless sudo (the unattended bootstrap needed it), and
# every agent runs as that same user: any agent shell command could become root with
# no prompt. This script closes that and a few smaller doors:
#
#   1. removes /etc/sudoers.d/90-devco (sudo asks for your password again)
#   2. makes the gateway config and the company scripts root-owned (agents can read,
#      not rewrite, the model routing or the QA script)
#   3. installs a global git pre-push hook that refuses pushes to main
#      (override for yourself with DEVCO_ALLOW_MAIN=1)
#   4. reminds you to replace the throwaway console password
#
# Undo for maintenance:  sudo /opt/devco/bin/devco unlock   (then lock again)
set -euo pipefail
source /opt/devco/devco.env
ME="${DEVCO_USER:-$USER}"

echo "==> Set a real password first (the install used a throwaway one that is public in git)."
read -r -p "    Has this account's password been changed with 'passwd' since the install? [y/N] " a
[[ "${a:-}" =~ ^[Yy]$ ]] || { echo "    Run: passwd   then re-run lockdown."; exit 1; }

echo "==> 1. Passwordless sudo off"
if [[ -f /etc/sudoers.d/90-devco ]]; then
  sudo rm -f /etc/sudoers.d/90-devco
  echo "    removed /etc/sudoers.d/90-devco"
else
  echo "    already removed"
fi

echo "==> 2. Root-owned gateway config and company scripts (read-only for agents)"
sudo chown root:root /opt/llama-swap/config.yaml && sudo chmod 644 /opt/llama-swap/config.yaml
sudo chown -R root:root /opt/devco/bin && sudo chmod -R a+rX,go-w /opt/devco/bin
sudo chown root:root /opt/devco/devco.env && sudo chmod 644 /opt/devco/devco.env
echo "    /opt/llama-swap/config.yaml, /opt/devco/bin, /opt/devco/devco.env -> root:root"

echo "==> 3. Global git pre-push hook: no pushes to main"
sudo mkdir -p /opt/devco/githooks
sudo tee /opt/devco/githooks/pre-push >/dev/null <<'EOF'
#!/usr/bin/env bash
# devco: refuse to push to main. Humans override with DEVCO_ALLOW_MAIN=1 git push ...
[[ "${DEVCO_ALLOW_MAIN:-0}" == "1" ]] && exit 0
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  case "$remote_ref" in
    refs/heads/main|refs/heads/master)
      echo "devco pre-push: pushing to $remote_ref is not allowed here. Open a pull request." >&2
      exit 1 ;;
  esac
done
exit 0
EOF
sudo chmod 755 /opt/devco/githooks/pre-push
git config --global core.hooksPath /opt/devco/githooks
echo "    core.hooksPath = /opt/devco/githooks (user $ME)"

echo "==> 4. What is NOT locked (by design)"
cat <<EOF
    - The agents can still read every repo under $DEVCO_REPOS and write to them:
      that is their job. GitHub is the backstop (bot has Write, you merge).
    - They can reach the LAN. Keep the NAS and anything with an admin UI behind
      credentials the box does not have (see SECRETS.md).
    - Docker: your user is NOT in the docker group; 'docker compose config' works
      without it, running containers does not. Add it only if ops really needs to.

Locked down. To edit the gateway config or re-run an installer later:
    sudo /opt/devco/bin/devco unlock     # chowns back to you
    ... do the work ...
    /opt/devco/bin/lockdown.sh           # lock again
EOF
# sudo caches the password you just typed for ~15 min, which makes "sudo -n true" look
# like passwordless sudo is still on. Forget it so the check below means something.
sudo -k
if sudo -n true 2>/dev/null; then
  echo "!! sudo still works without a password: check 'sudo -l' and /etc/sudoers.d/" >&2; exit 1
else
  echo "Check: sudo now asks for a password (sudo -n true fails). Lockdown verified."
fi
