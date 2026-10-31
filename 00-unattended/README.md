# Unattended install: USB in, models serving out

Boot the box from an Ubuntu Server USB with a second small USB stick plugged in, answer
one prompt, walk away. About an hour later (most of it the 80 GB model download) the box
is sitting at the end of README Phase 1: kernel parameters applied, llama.cpp built,
both models resident on the gateway. No typing on the box at all.

What it replaces: the OS install screens, Phase 0, the reboot, and Phase 1.
What it can't replace: the browser logins in Phase 2+ (`03-paperclip/logins.sh`
batches them).

## 1. Make the two USB sticks (on your PC)

**Stick A, the installer:** download Ubuntu Server 25.10 (amd64) and write it to a USB
with Rufus (Windows) or `dd` (Linux/Mac). Nothing else goes on this stick.

**Stick B, the answers:** any small USB stick, formatted **FAT32** with the volume label
**`CIDATA`** (exactly that, uppercase). Two files in its root:

- `meta-data` — an empty file (zero bytes)
- `user-data` — a copy of `autoinstall.yaml` with the four placeholders filled in

## 2. Fill in the placeholders

Open `autoinstall.yaml` in a text editor and find-and-replace all four. `__USERNAME__`
appears many times; replace every occurrence.

| Placeholder | Value | How to get it |
|---|---|---|
| `__USERNAME__` | your Linux username on the box, e.g. `geoff` | lowercase, no spaces |
| `__PASSWORD_HASH__` | a SHA-512 hash of your password | on your PC: `openssl passwd -6` (Git Bash on Windows has it), paste the whole `$6$...` string |
| `__SSH_PUBLIC_KEY__` | your PC's public key, one line starting `ssh-ed25519` | `cat ~/.ssh/id_ed25519.pub`; if you have none: `ssh-keygen -t ed25519` |
| `__REPO_TOKEN__` | a GitHub token that can read this repo | below |

**The token.** GitHub → Settings → Developer settings → Personal access tokens →
**Fine-grained tokens** → Generate new token. Resource owner: `spidersnet-devco`.
Repository access: only `devco-infra`. Permissions: Contents **Read-only**. Expiration:
**1 day**. Copy it into `__REPO_TOKEN__`. The bootstrap removes it from the box after
cloning and it expires anyway; delete the token on GitHub once the box is up.

Save the result as `user-data` on stick B. The file must start with `#cloud-config` on
line 1.

## 3. Boot

1. Plug both sticks in, boot the MS-S1 Max from stick A (F7 or Del for the boot menu,
   depending on the firmware).
2. The installer finds stick B and asks **"Continue with autoinstall? (yes/no)"**.
   Type `yes`. That is the only interaction. It then **erases the internal NVMe**.
3. ~10 minutes: the box reboots. Pull stick A when it does (stick B can stay or go).
4. 1st boot: base packages, kernel params, reboot again (~5 min).
5. 2nd boot: llama.cpp build, model download, gateway up (~40–60 min, mostly download).

Watch from your PC:

```bash
ssh <username>@hermes.local          # or the IP from your router
tail -f /opt/devco/bootstrap.log
```

Done when the log says `stage 1 done` and `http://127.0.0.1:8080/ui` (tunnel:
`ssh -L 8080:127.0.0.1:8080 <username>@hermes.local`) shows both models running.

## If it stops

`/opt/devco/.bootstrap-FAILED` exists and names the stage and reason. Fix the cause
(the log has the script output), then:

```bash
sudo systemctl start devco-bootstrap      # re-runs the current stage
```

Common ones:

| Symptom | Cause |
|---|---|
| "Continue with autoinstall?" never appears | Stick B isn't labeled `CIDATA`, or `user-data` doesn't start with `#cloud-config` |
| Installer stops at a storage error | Another disk is present; the `match: size: largest` picked the wrong one. Unplug it. |
| stage 0 FAILED: no network | The 10 GbE port needs a driver the installer lacked, or the box is on the Wi-Fi only. Plug into the port that worked during install. |
| stage 1 FAILED: GTT | Kernel params didn't take. `cat /proc/cmdline` should show `amdgpu.gttsize`. See `01-base/strix-halo-kernel.md`. |
| Model download failed | Hugging Face hiccup. `sudo systemctl start devco-bootstrap` resumes the download. |

## What's deliberately NOT automated

- The password hash and token go on a USB stick you hold. Wipe stick B afterwards.
- `/etc/sudoers.d/90-devco` grants passwordless sudo to your user so the bootstrap can
  run unattended. Keep it (convenient for a homelab box) or delete it when done.
- Everything from Phase 2 on needs your logins and your approvals. See the README.
