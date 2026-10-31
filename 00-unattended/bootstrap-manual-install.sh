#!/usr/bin/env bash
# 00-unattended/bootstrap-manual-install.sh
# For a box installed BY HAND (the normal Ubuntu installer screens) instead of the
# unattended install. Installs the same first-boot automation the unattended path
# gets from its late-commands, then starts it. Run ONCE, as your normal user:
#
#   git clone https://github.com/spidersnet-devco/devco-infra.git ~/devco-infra
#   sudo bash ~/devco-infra/00-unattended/bootstrap-manual-install.sh
#
# What it does: passwordless sudo for your user (lockdown.sh removes it later),
# /opt/devco + stage file, the devco-bootstrap service, linger, then starts stage 0.
# Stage 0 REBOOTS the box after ~5 minutes (kernel parameters); stages 1 and 2 run
# after the reboot on their own. Watch: tail -f /opt/devco/bootstrap.log
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo bash "$0" "$@"
U="${SUDO_USER:-}"
[[ -n "$U" && "$U" != "root" ]] || { echo "Run this with sudo from your normal user, not as root."; exit 1; }
H="$(getent passwd "$U" | cut -d: -f6)"
UID_N="$(id -u "$U")"
REPO="$H/devco-infra"
[[ -d "$REPO/.git" ]] || { echo "Clone the repo first:  git clone https://github.com/spidersnet-devco/devco-infra.git $REPO"; exit 1; }
[[ -f /opt/devco/.bootstrap-done ]] && { echo "Bootstrap already finished on this box (/opt/devco/.bootstrap-done exists)."; exit 0; }

echo "==> 1. Passwordless sudo for $U (the bootstrap runs unattended; lockdown.sh removes this later)"
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-devco
chmod 0440 /etc/sudoers.d/90-devco

echo "==> 2. /opt/devco and the stage file"
mkdir -p /opt/devco
[[ -f /opt/devco/.bootstrap-stage ]] || echo 0 > /opt/devco/.bootstrap-stage
chown -R "$U:$U" /opt/devco

echo "==> 3. The bootstrap script and service"
install -m 0755 "$REPO/00-unattended/devco-bootstrap.sh" /usr/local/sbin/devco-bootstrap.sh
sed "s/@@USER@@/$U/g; s/@@UID@@/$UID_N/g" "$REPO/00-unattended/devco-bootstrap.service" > /etc/systemd/system/devco-bootstrap.service
systemctl daemon-reload
systemctl enable devco-bootstrap.service >/dev/null 2>&1

echo "==> 4. Linger (user services keep running without a login session)"
loginctl enable-linger "$U"

echo "==> 5. Starting stage $(cat /opt/devco/.bootstrap-stage)"
systemctl start --no-block devco-bootstrap.service
cat <<EOF

Started. Watch it with:

    tail -f /opt/devco/bootstrap.log

Stage 0 (~5 min) installs the base packages and kernel parameters, then REBOOTS
the box. After the reboot, stages 1 and 2 run on their own (~1 h, mostly the 86 GB
model download) and end with "ALL UNATTENDED WORK FINISHED". Then: README Phase 2.
If it stops, /opt/devco/.bootstrap-FAILED says why; fix, then:
    sudo systemctl start --no-block devco-bootstrap
EOF
