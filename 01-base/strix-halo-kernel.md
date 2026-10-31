# Strix Halo (Ryzen AI Max+ 395) on Linux: letting the iGPU use the full 128 GB

This is the one step that is easy to skip and impossible to debug later. Without it
the Radeon 8060S can only address a small slice of system RAM and gpt-oss-120b will
fail to load or spill to CPU.

## 1. BIOS

Leave the iGPU "UMA / dedicated VRAM" setting at its **default or minimum** (not 96 GB).
On Linux the driver reaches the rest of RAM through GTT (below). A big dedicated
carve-out just steals memory from everything else on the box. Set the TDP/power
profile to the higher setting (120 W class) if the MS-S1 Max exposes it; it helps
7B+ models noticeably.

## 2. Kernel parameters

Edit `/etc/default/grub` and add to `GRUB_CMDLINE_LINUX_DEFAULT`:

```
iommu=pt amdgpu.gttsize=131072 ttm.pages_limit=33554432
```

| Parameter | What it does |
|---|---|
| `iommu=pt` | IOMMU passthrough; less overhead for unified-memory access |
| `amdgpu.gttsize=131072` | GPU translation table sized to 128 GB (MiB) |
| `ttm.pages_limit=33554432` | TTM pinned-page limit = 128 GB (33554432 × 4 KB) |

Then:

```bash
sudo update-grub          # Ubuntu/Debian
# sudo grub2-mkconfig -o /boot/grub2/grub.cfg   # Fedora
```

Make it persistent for the module as well:

```bash
cat <<'EOF' | sudo tee /etc/modprobe.d/amdgpu_llm.conf
options amdgpu gttsize=131072
options ttm pages_limit=33554432
EOF
sudo reboot
```

## 3. Verify

```bash
cat /sys/class/drm/card*/device/mem_info_gtt_total
# expect ~137438953472 (128 GB)
vulkaninfo --summary | grep -i 8060S
```

## 4. Kernel / Mesa versions

- Kernel **6.14 or newer** (6.18-class is what the community benchmarks use).
- Mesa **25.x** for a RADV that knows gfx1151. Fedora 42+ and Ubuntu 26.04 LTS are fine out
  of the box. Ubuntu 24.04 LTS needs the HWE kernel plus a newer Mesa.
- linux-firmware **20260110 or newer** (one earlier release broke ROCm on this chip).

If your distro's Mesa is too old, skip the host build and use the community toolbox
container instead (`02-models/install-llamacpp.sh --container`), which ships its own
Mesa/Vulkan.

## 5. Backend choice

As of early-to-mid 2026, ROCm/HIP on gfx1151 is still hit-or-miss on newer kernels.
**Vulkan (RADV) is the reliable path** and is actually faster at token generation; ROCm
wins on prompt processing when it works. The package defaults to Vulkan. Revisit ROCm
later if prefill speed becomes the bottleneck.
