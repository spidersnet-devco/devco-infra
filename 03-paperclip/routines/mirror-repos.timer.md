# Nightly repo mirror as a systemd user timer

The mirror runs as a plain timer, not a Paperclip routine, so it works even when the
company is paused. Install once:

```bash
mkdir -p ~/.config/systemd/user /opt/devco/bin
install -m 0755 03-paperclip/routines/mirror-repos.sh /opt/devco/bin/mirror-repos.sh

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

Needs `GIT_MIRROR_DIR` in `/opt/devco/devco.env` to point at a mounted NAS share (for
example an NFS or SMB mount of an Unraid `backups` share). If the share isn't mounted,
the script creates a local directory there instead, so check the path once.
