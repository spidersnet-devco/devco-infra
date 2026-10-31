# Unattended install, pulled from GitHub

Boot the box from a stock Ubuntu Server USB, type one line at the boot menu, walk
away. About an hour later (most of it the 86 GB model download) the box has: kernel
parameters applied, llama.cpp built, both models resident on the gateway, Paperclip
running as a service, Hermes installed with its three profiles, and the GitHub bot's
SSH key generated. The installer reads its answers from this folder on GitHub;
nothing is typed on the box and there is no second USB stick.

What it replaces: the installer screens, Phases 0, 1, and the no-login parts of 2 and 3.
What it can't replace: the installer stick itself, and the logins (`03-paperclip/logins.sh`
batches those into one five-minute session).

## 0. The box

| | |
|---|---|
| Firmware keys | **F7** = boot-device menu, **Del** = setup. If neither reacts (Fast Boot), get into setup from Windows: Settings → Recovery → Advanced startup → UEFI Firmware Settings. |
| Firmware settings | Fast Boot **off**. Secure Boot can stay **on** (Ubuntu is signed; nothing here needs an unsigned module). iGPU memory at default/minimum. |
| Network | Wired. The two 10 GbE ports are Realtek RTL8127 chips supported only from kernel 6.16 on: **26.04 works, a 24.04 stick has no network at all** and the install silently turns interactive. Either port is fine; the config uses both with DHCP. |
| Disk | The stock 2 TB NVMe. The install **erases the largest disk** without asking; unplug anything else. |
| Boot mode | UEFI only (no legacy CSM). In Rufus choose **GPT** + **UEFI (non CSM)**. |

## 1. The repo must be public

The installer fetches `user-data` from `raw.githubusercontent.com`, which only works
for public repos without credentials. This repo holds no secrets (every `.env` and the
real `devco.env` are gitignored), and `user-data` contains only your username, your SSH
*public* key, and a throwaway password hash. Repo → Settings → General → Danger Zone →
**Change visibility → Public**. You can flip it back to private once the box is built.

**Private-repo alternative (no second stick):** write the installer USB with Rufus in
*ISO mode* (the default; it gives a writable FAT partition), then copy your filled-in
`user-data` onto the stick as `autoinstall.yaml` next to the `casper` folder. The
installer finds it there. You still add the single word `autoinstall` at the GRUB
line (step 3) and you must replace the `git clone https://...` late-command with a
token-bearing URL or an SSH deploy key. Ask when you need it.

## 2. Fill in the three placeholders

`user-data` has three placeholders in double underscores. `__USERNAME__` appears many
times; replace every occurrence. Easiest is Claude Code on your PC, in your clone:

```
In 00-unattended/user-data replace every __USERNAME__ with geoff, __SSH_PUBLIC_KEY__
with the single line from ~/.ssh/id_ed25519.pub (create the key with
ssh-keygen -t ed25519 if it doesn't exist), and __PASSWORD_HASH__ with the output of
`openssl passwd -6` for a long random throwaway password you generate and show me
once. Confirm the file still starts with #cloud-config and parses as YAML, then
commit and push, and tell me the short commit SHA.
```

By hand instead:

| Placeholder | Value | How |
|---|---|---|
| `__USERNAME__` | your Linux username, e.g. `geoff` | lowercase, no spaces |
| `__SSH_PUBLIC_KEY__` | your PC's public key, one line starting `ssh-ed25519` | `cat ~/.ssh/id_ed25519.pub` (Git Bash on Windows works) |
| `__PASSWORD_HASH__` | SHA-512 hash of a *throwaway* password | `openssl passwd -6`, paste the whole `$6$...` string |

Make the throwaway password long and random: the hash is public, and short passwords
are cheap to brute-force. It only matters at the physical console (SSH is key-only,
sudo is passwordless until lockdown). Change it after your first login with `passwd`.

Push. Then either **wait five minutes** (GitHub caches raw files for 300 s) and check
that this URL shows your filled-in file:

```
https://raw.githubusercontent.com/spidersnet-devco/devco-infra/main/00-unattended/user-data
```

or skip the wait by using the commit SHA instead of `main` in the kernel line below.
The SHA form also pins the install to exactly the revision you reviewed.

## 3. Make the installer stick (on your PC)

Download **Ubuntu Server 26.04.1 LTS** (`ubuntu-26.04.1-live-server-amd64.iso`, 2.7 GB) and
write it to a USB with Rufus (GPT, UEFI non-CSM, ISO mode) or `dd`. Nothing custom
goes on it; it's the stock installer.

## 4. Boot

1. Plug the stick into the MS-S1 Max and boot from it (F7). Wired, DHCP.
2. At the GRUB menu, highlight **Try or Install Ubuntu Server** and press **`e`**.
3. Find the line starting with `linux`. Put the cursor just before `---` on that line
   (or at the end if there is no `---`) and type, as one line, quotes included:

   ```
   autoinstall 'ds=nocloud;s=https://raw.githubusercontent.com/spidersnet-devco/devco-infra/main/00-unattended/'
   ```

   (`main` → your commit SHA to skip the cache wait. The quotes matter: an unquoted
   `;` ends the GRUB command. Older guides write `nocloud-net` and `\;`; both still work.)
4. Press **Ctrl-X**. That's the whole interaction. The installer fetches `user-data`,
   **erases the internal NVMe**, installs, and reboots in ~10 minutes. Pull the stick
   when it reboots.
5. 1st boot: base packages, kernel params, reboot again (~5 min).
6. 2nd boot: llama.cpp build, model download, gateway, Paperclip, Hermes (~60 min, mostly download).

Watch from your PC:

```bash
ssh geoff@hermes.local                  # avahi is installed, so .local works; or use the
tail -f /opt/devco/bootstrap.log        # IP: the log prints DEVCO_LAN_IP in stage 0
```

Done when the log says `ALL UNATTENDED WORK FINISHED`. Then `http://127.0.0.1:8080/ui`
(tunnel: `ssh -L 8080:127.0.0.1:8080 geoff@hermes.local`) shows both models **ready**,
and `http://<LAN IP>:3100` shows Paperclip's claim page.

## If it stops

`/opt/devco/.bootstrap-FAILED` exists and names the stage and reason. Fix the cause
(the log has the script output), then:

```bash
sudo systemctl start --no-block devco-bootstrap    # re-runs the current stage; watch the log
```

| Symptom | Cause |
|---|---|
| Installer shows its normal screens instead of running on its own | The kernel line didn't take, the URL 404s, or (24.04 stick) the NIC has no driver. Check the raw URL in a browser. |
| "autoinstall config did not validate" | A placeholder is still there, or the YAML broke. The raw URL in a browser shows what the installer saw. |
| Installer can't fetch the seed, TLS error | The box's clock is wrong (new machine, dead CMOS battery). Set the date in firmware setup. |
| Installer stops at a storage error | Another disk is present; `match: size: largest` picked the wrong one. Unplug it. |
| stage 0 FAILED: no network | Box is on Wi-Fi only, or the cable moved to a port that was down during install (the network block in `user-data` should cover both ports; check `ip a`). |
| stage 1 FAILED: GTT | Kernel params didn't take. `cat /proc/cmdline` should show `ttm.pages_limit`. See `01-base/strix-halo-kernel.md`. |
| Model download failed | Hugging Face hiccup. `sudo systemctl start --no-block devco-bootstrap` resumes it; `hf download` picks up where it stopped. |
| stage 2: one step failed | The log names the step. Each is idempotent; re-run the stage or run that script by hand. |

## Installed by hand instead?

If you went through the normal installer screens (make root use the **whole disk** in
the storage screen; the default stops at 100 GB), you can still get the same
first-boot automation afterwards:

```bash
git clone https://github.com/spidersnet-devco/devco-infra.git ~/devco-infra
sudo bash ~/devco-infra/00-unattended/bootstrap-manual-install.sh
tail -f /opt/devco/bootstrap.log        # stage 0 reboots once; stages 1-2 follow on their own
```

## Zero USB at all (later, optional)

The one remaining stick can go too: install **netboot.xyz** from Unraid's Community
Apps and point your router's DHCP boot options (66/67) at it. The box then PXE-boots
the Ubuntu installer over the LAN, and netboot.xyz lets you set the same `autoinstall`
kernel argument once in its menu. It's a separate afternoon; not needed for the first
build.

## What's deliberately NOT automated

- Logins (Claude, Codex, GitHub as the bot, Paperclip claim): `03-paperclip/logins.sh`.
- Building the company in Paperclip (CEO instructions, agents, budgets):
  `03-paperclip/create-company.sh`, run once after the logins.
- `/etc/sudoers.d/90-devco` grants passwordless sudo to your user so the bootstrap can
  run unattended. **The agents run as the same user**, so until you run
  `03-paperclip/lockdown.sh` every agent effectively has root. Run it when Phase 3 is done.
