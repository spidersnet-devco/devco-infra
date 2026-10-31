# Nightly repo mirror as a systemd user timer

The mirror runs as a plain timer, not a Paperclip routine, so it works even when the
company is paused. `install-paperclip.sh` installs the script; `devco mirror-timer`
installs the units below (or do it by hand):

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/mirror-repos.service <<'EOF'
[Unit]
Description=Mirror all spidersnet-devco repos to the NAS
[Service]
Type=oneshot
ExecStart=/opt/devco/bin/mirror-repos.sh
EOF

cat > ~/.config/systemd/user/mirror-repos.timer <<'EOF'
[Unit]
Description=Nightly repo mirror
[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now mirror-repos.timer
systemctl --user start mirror-repos.service     # run once now
journalctl --user -u mirror-repos -n 20
```

Needs `GIT_MIRROR_DIR` in `/opt/devco/devco.env` to point at a **mounted** NAS share
(an NFS or SMB mount of an Unraid `backups` share, in `/etc/fstab` with `nofail`). The
script refuses to run when that path is not on a mount, so an unmounted share can't
silently fill the root disk; set `GIT_MIRROR_REQUIRE_MOUNT=0` to allow a local
directory. The standup routine reports the last mirror line, so you notice if it stops.
