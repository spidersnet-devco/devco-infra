#!/usr/bin/env bash
# 01-base/apply-kernel-params.sh
# Idempotently applies the Strix Halo unified-memory kernel parameters
# (see strix-halo-kernel.md). Safe to re-run; replaces older values of the same
# parameters. Does NOT reboot.
#
#   bash 01-base/apply-kernel-params.sh && sudo reboot
set -euo pipefail

# 124 GiB for the GPU (the community value): the GPU can never pin the last
# 4 GiB, so a runaway allocation fails cleanly instead of OOM-killing the host.
#   ttm.pages_limit   is what current kernels (6.18+/7.0) actually use
#   amdgpu.gttsize    is deprecated on those kernels (one dmesg warning) but
#                     still honoured by older ones; the two values agree.
PARAMS="iommu=pt ttm.pages_limit=32505856 amdgpu.gttsize=126976"
MANAGED_KEYS="ttm.pages_limit amdgpu.gttsize iommu"

if [[ -f /etc/default/grub ]]; then
  CUR="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | head -1 | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"$/\1/')"
  NEW=""
  for tok in $CUR; do                      # drop any previous value of the keys we manage
    keep=1
    for k in $MANAGED_KEYS; do [[ "$tok" == "$k="* ]] && keep=0; done
    (( keep )) && NEW="$NEW $tok"
  done
  NEW="$(echo "$NEW $PARAMS" | xargs)"      # append ours, trim
  if [[ "$NEW" != "$CUR" ]]; then
    sudo cp /etc/default/grub "/etc/default/grub.bak.$(date +%Y%m%d-%H%M%S)"
    if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
      sudo sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW\"|" /etc/default/grub
    else
      echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW\"" | sudo tee -a /etc/default/grub >/dev/null
    fi
    echo "==> GRUB_CMDLINE_LINUX_DEFAULT: \"$CUR\" -> \"$NEW\""
    sudo update-grub
  else
    echo "==> GRUB already has the parameters"
  fi
else
  echo "!! /etc/default/grub not found; add these to your bootloader by hand: $PARAMS"
fi

# Same values for the module, so they apply even if the GRUB line is lost.
# amdgpu loads from the initramfs on Ubuntu, so the initramfs must be rebuilt.
cat <<'EOF' | sudo tee /etc/modprobe.d/amdgpu_llm.conf >/dev/null
# Strix Halo: let the iGPU address (almost) all of system RAM. See 01-base/strix-halo-kernel.md
options ttm pages_limit=32505856
options amdgpu gttsize=126976
EOF
echo "==> /etc/modprobe.d/amdgpu_llm.conf written; rebuilding initramfs"
sudo update-initramfs -u >/dev/null 2>&1 || echo "   (update-initramfs failed or not present; GRUB line still applies)"

if ls /sys/class/drm/card*/device/mem_info_gtt_total >/dev/null 2>&1; then
  CUR_GTT="$(cat /sys/class/drm/card*/device/mem_info_gtt_total 2>/dev/null | sort -n | tail -1)"
  echo "==> current GTT total: ${CUR_GTT:-?} bytes (after reboot expect ~133 GB = 124 GiB; anything >= 120 GB is fine)"
fi
echo "==> Reboot to apply."
