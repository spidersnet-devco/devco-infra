#!/usr/bin/env bash
# 01-base/apply-kernel-params.sh
# Idempotently applies the Strix Halo unified-memory kernel parameters
# (see strix-halo-kernel.md). Safe to re-run. Does NOT reboot.
#
#   bash 01-base/apply-kernel-params.sh && sudo reboot
set -euo pipefail

PARAMS="iommu=pt amdgpu.gttsize=131072 ttm.pages_limit=33554432"

if [[ -f /etc/default/grub ]]; then
  # Debian/Ubuntu (and Fedora, which also honours GRUB_CMDLINE_LINUX_DEFAULT)
  CUR="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | head -1 | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"$/\1/')"
  NEW="$CUR"
  for p in $PARAMS; do
    [[ " $NEW " == *" $p "* ]] || NEW="$NEW $p"
  done
  NEW="$(echo "$NEW" | xargs)"   # trim
  if [[ "$NEW" != "$CUR" ]]; then
    sudo cp /etc/default/grub "/etc/default/grub.bak.$(date +%Y%m%d-%H%M%S)"
    if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
      sudo sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW\"|" /etc/default/grub
    else
      echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW\"" | sudo tee -a /etc/default/grub >/dev/null
    fi
    echo "==> GRUB_CMDLINE_LINUX_DEFAULT: \"$CUR\" -> \"$NEW\""
    if command -v update-grub >/dev/null 2>&1; then sudo update-grub
    elif command -v grub2-mkconfig >/dev/null 2>&1; then sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
  else
    echo "==> GRUB already has the parameters"
  fi
else
  echo "!! /etc/default/grub not found; add these to your bootloader by hand: $PARAMS"
fi

cat <<'EOF' | sudo tee /etc/modprobe.d/amdgpu_llm.conf >/dev/null
# Strix Halo: let the iGPU address (almost) all of system RAM
options amdgpu gttsize=131072
options ttm pages_limit=33554432
EOF
echo "==> /etc/modprobe.d/amdgpu_llm.conf written"

if [[ -r /sys/class/drm/card0/device/mem_info_gtt_total ]] || ls /sys/class/drm/card*/device/mem_info_gtt_total >/dev/null 2>&1; then
  CUR_GTT="$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | sort -n | tail -1)"
  echo "==> current GTT total: ${CUR_GTT:-?} bytes (need ~137438953472 after reboot)"
fi
echo "==> Reboot to apply."
