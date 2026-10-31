# Unattended install, pulled from GitHub

Boot the box from a stock Ubuntu Server USB, type one line at the boot menu, walk
away. About an hour later (most of it the 80 GB model download) the box is sitting at
the end of README Phase 1: kernel parameters applied, llama.cpp built, both models
resident on the gateway. The installer reads its answers from this folder on GitHub;
nothing is typed on the box and there is no second USB stick.

What it replaces: the installer screens, Phase 0, the reboot, and Phase 1.
What it can't replace: the installer stick itself, and the browser logins in Phase 2+
(`03-paperclip/logins.sh` batches those).

## 0. The repo must be public

The installer fetches `user-data` from `raw.githubusercontent.com`, which only works
for public repos without credentials. This repo holds no secrets (every `.env` and the
real `devco.env` are gitignored), and `user-data` contains only your username, your SSH
*public* key, and a throwaway password hash. Repo → Settings → General → Danger Zone →
**Change visibility → Public**.

If you'd rather keep it private, the same `user-data` works from a second USB stick
labeled `CIDATA` (put `user-data` and `meta-data` in its root), with one extra
`late-command` to clone using a token. That's the old method; ask if you need it.

## 1. Fill in the three placeholders

`user-data` has three `__PLACEHOLDERS__`. `__USERNAME__` appears many times; replace
every occurrence. Easiest is Claude Code on your PC, in your clone of this repo:

```
In 00-unattended/user-data replace every __USERNAME__ with geoff, __SSH_PUBLIC_KEY__
with the single line from ~/.ssh/id_ed25519.pub (create the key with
ssh-keygen -t ed25519 if it doesn't exist), and __PASSWORD_HASH__ with the output of
`openssl passwd -6` for a throwaway password you generate and show me once. Confirm
the file still starts with #cloud-config and parses as YAML, then commit and push.
```

By hand instead:

| Placeholder | Value | How |
|---|---|---|
| `__USERNAME__` | your Linux username, e.g. `geoff` | lowercase, no spaces |
| `__SSH_PUBLIC_KEY__` | your PC's public key, one line starting `ssh-ed25519` | `cat ~/.ssh/id_ed25519.pub` (Git Bash on Windows works) |
| `__PASSWORD_HASH__` | SHA-512 hash of a *throwaway* password | `openssl passwd -6`, paste the whole `$6$...` string |

The password only matters at the physical console: SSH is key-only and sudo is
passwordless. Change it after your first login with `passwd`.

Push, then **wait about five minutes**: GitHub's raw file cache lags behind pushes.
Check in a browser that this URL shows your filled-in file:

```
https://raw.githubusercontent.com/spidersnet-devco/devco-infra/main/00-unattended/user-data
```

## 2. Make the installer stick (on your PC)

Download Ubuntu Server **26.04 LTS** (amd64, the 3 GB "Intel or AMD 64-bit" image) and write it to a USB with Rufus (Windows) or
`dd`. Nothing custom goes on it; it's the stock installer.

## 3. Boot

1. Plug the stick into the MS-S1 Max, boot from it (F7 or Del for the boot menu,
   depending on the firmware). Make sure the box is on a wired port with DHCP.
2. At the GRUB menu, highlight **Try or Install Ubuntu Server** and press **`e`**.
3. Find the line starting with `linux`. Put the cursor just before `---` on that line
   and type (one line, including the quotes):

   ```
   autoinstall 'ds=nocloud-net;s=https://raw.githubusercontent.com/spidersnet-devco/devco-infra/main/00-unattended/'
   ```

   (The trailing slash matters. Older guides write the semicolon as `\;` instead of
   using quotes; either works.)
4. Press **Ctrl-X**. That's the whole interaction. The installer fetches `user-data`,
   **erases the internal NVMe**, installs, and reboots in ~10 minutes. Pull the stick
   when it reboots.
5. 1st boot: base packages, kernel params, reboot again (~5 min).
6. 2nd boot: llama.cpp build, model download, gateway up (~40–60 min, mostly download).

Watch from your PC:

```bash
ssh geoff@hermes.local               # or the IP from your router's DHCP list
tail -f /opt/devco/bootstrap.log
```

Done when the log says `stage 1 done` and `http://127.0.0.1:8080/ui` (tunnel:
`ssh -L 8080:127.0.0.1:8080 geoff@hermes.local`) shows both models running.

## If it stops

`/opt/devco/.bootstrap-FAILED` exists and names the stage and reason. Fix the cause
(the log has the script output), then:

```bash
sudo systemctl start devco-bootstrap      # re-runs the current stage
```

| Symptom | Cause |
|---|---|
| Installer shows its normal screens instead of running on its own | The kernel line didn't take, or the URL 404s. Check the raw URL in a browser; mind the trailing slash. |
| "autoinstall config did not validate" | A placeholder is still there, or the YAML broke. The raw URL in a browser shows what the installer saw. |
| Installer stops at a storage error | Another disk is present; `match: size: largest` picked the wrong one. Unplug it. |
| stage 0 FAILED: no network | Box is on Wi-Fi only, or the 10 GbE port that worked during install isn't the one plugged in now. |
| stage 1 FAILED: GTT | Kernel params didn't take. `cat /proc/cmdline` should show `amdgpu.gttsize`. See `01-base/strix-halo-kernel.md`. |
| Model download failed | Hugging Face hiccup. `sudo systemctl start devco-bootstrap` resumes it. |

## Zero USB at all (later, optional)

The one remaining stick can go too: install **netboot.xyz** from Unraid's Community
Apps and point your router's DHCP boot options (66/67) at it. The box then PXE-boots
the Ubuntu installer over the LAN, and netboot.xyz lets you set the same `autoinstall`
kernel argument once in its menu. It's a separate afternoon; not needed for the first
build.

## What's deliberately NOT automated

- `/etc/sudoers.d/90-devco` grants passwordless sudo to your user so the bootstrap can
  run unattended. Keep it (convenient for a homelab box) or delete it when done.
- Everything from Phase 2 on needs your logins and your approvals. See the README.
