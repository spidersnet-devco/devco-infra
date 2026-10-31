# Strix Halo (Ryzen AI Max+ 395) on Linux: letting the iGPU use (almost) all 128 GB

This is the one step that is easy to skip and impossible to debug later. Without it
the Radeon 8060S can only address half of system RAM (the TTM default is 50%), and
gpt-oss-120b will fail to load or spill to CPU.

`01-base/apply-kernel-params.sh` does everything below; the unattended install runs
it on first boot. This page is the explanation.

## 1. BIOS

Leave the iGPU "UMA / dedicated VRAM" setting at its **default or minimum** (not 96 GB).
On Linux the driver reaches the rest of RAM through GTT (below). A big dedicated
carve-out just steals memory from everything else on the box. Set the TDP/power
profile to the higher setting (120 W class) if the MS-S1 Max exposes it. Turn **Fast
Boot off** (it hides the boot menu keys). Secure Boot can stay on: Ubuntu's kernel
is signed and nothing here needs an out-of-tree module.

## 2. Kernel parameters

`GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` gets:

```
iommu=pt ttm.pages_limit=32505856 amdgpu.gttsize=126976
```

| Parameter | What it does |
|---|---|
| `iommu=pt` | IOMMU passthrough; less overhead for unified-memory access. (`amd_iommu=off` is 5–12 % faster but disables the NPU and DMA protection.) |
| `ttm.pages_limit=32505856` | TTM pinned-page limit = 124 GiB (pages × 4 KiB). **This is the one that matters** on kernel 6.18+/7.0: GTT size is derived from it. Default is 50 % of RAM. |
| `amdgpu.gttsize=126976` | Same 124 GiB in MiB, for kernels before 6.18. On 7.0 it is deprecated: `dmesg` shows one "Configuring gttsize via module parameter is deprecated" line, which is expected. |

Why 124 GiB and not 128: the GPU can then never pin the last 4 GiB, so a runaway
allocation fails cleanly instead of the kernel OOM-killing the gateway or sshd.

The same values go in `/etc/modprobe.d/amdgpu_llm.conf`, followed by
`update-initramfs -u` (amdgpu loads from the initramfs on Ubuntu, so without the
rebuild the modprobe file is dead weight). Then reboot.

## 3. Verify

```bash
cat /sys/class/drm/card*/device/mem_info_gtt_total
# expect ~133143986176 (124 GiB). On kernels >= 7.1 it is capped to available RAM
# and reads a little lower. Anything >= 120 GB is right; ~64 GB means it didn't apply.
cat /proc/cmdline | tr ' ' '\n' | grep -E 'ttm|gttsize|iommu'
vulkaninfo --summary | grep -i 8060S      # "AMD Radeon 8060S Graphics (RADV GFX1151)"
```

## 4. Kernel / Mesa versions

Ubuntu **26.04 LTS** ships kernel 7.0 and Mesa 26.0, both fine out of the box
(RADV has known gfx1151 since Mesa 25.0). Two hardware notes for this exact box:

- The two 10 GbE ports are **Realtek RTL8127**, in-tree only since kernel 6.16. A
  24.04 installer (kernel 6.8) has no network on them at all, so never fall back to it.
- linux-firmware **20251125** broke ROCm on this chip and was recalled; 26.04's
  firmware is newer. Only relevant if you ever switch to ROCm.

## 5. Backend choice: Vulkan by default, ROCm as the escape hatch

Measured on Strix Halo with gpt-oss-120b MXFP4 (kyuz0's published runs, 2026):

| | prompt processing 512 | generation | pp @ 32K ctx | pp @ 64K ctx |
|---|---|---|---|---|
| Vulkan RADV | 720 t/s | 57 t/s | 307 | 146 |
| ROCm 7.2 | 626 t/s | 52 t/s | 589 | 371 |

Vulkan wins generation and stability and is the default here. ROCm (7.2+ / 10.0)
now works on gfx1151 and on 7.x kernels, and wins prompt processing by 2–2.5× at
32–64K context. Prompt caching hides most of that for agent turns. If long prompts
ever become the bottleneck, `02-models/install-llamacpp.sh --container rocm` pulls
kyuz0's `rocm-10.0` toolbox; don't install host ROCm on 26.04.
