# Secrets: what is secret, where it lives, what never goes in this repo

This repo is **public** (the unattended installer needs it to be). Assume everything
in it is read by strangers. The rule: configuration here, credentials elsewhere.

| Secret | Where it lives on the box | Who wrote it | Never |
|---|---|---|---|
| Your Claude Max login | `~/.claude/.credentials.json` (OAuth, refreshes itself) | `claude auth login` | in this repo, in `devco.env`, in a ticket |
| Your ChatGPT Plus login | `~/.codex/auth.json` | `codex login --device-auth` | same |
| The bot's GitHub login | `~/.config/gh/hosts.yml` | `gh auth login` as the bot | same |
| The bot's SSH key | `~/.ssh/id_ed25519_devco_bot` (+ `.pub`) | `github-setup.sh` | the private half anywhere else; the public half is fine to paste |
| Paperclip board CLI key (30-day) | Paperclip's private auth store under `~/.paperclip/` | `paperclipai auth login` | same |
| Paperclip run keys for agents | minted per run, injected into the agent's environment | Paperclip | copied into profile `.env` files (not needed with `hermes_local`) |
| Athena gateway key (later) | `~/.config/llama-swap.env` (mode 600) | you | `llama-swap.yaml`, the unit file, this repo |
| Throwaway console password | its **hash** is public in `user-data` by design | you | reused anywhere; change it with `passwd` after first login |

`/opt/devco/devco.env` is **not** a secrets file: every agent on the box can read it.
It holds hostnames, paths, and account *names*. `devco check-env` warns if something
that looks like a key lands in it.

## Why the agents can't leak your accounts

- They never see your GitHub login. They push as the bot, whose Write access you can
  revoke in one click (`03-paperclip/agents/github-access.md`).
- They never see your Claude or ChatGPT credentials as text: Paperclip runs the
  `claude`/`codex` CLIs, which read their own credential files. An agent *could* read
  those files (same Unix user) — which is why `lockdown.sh` matters and why the box
  should not hold anything else of yours.
- Hermes profiles redact secrets from tool output (`security.redact_secrets: true`).
- Paperclip's run log redacts tokens it knows about; the agents are told to use
  `$PAPERCLIP_API_KEY` rather than printing it.

## When something leaks anyway

1. GitHub: bot account → Settings → SSH keys → delete; org → People → remove the bot;
   `gh auth logout` on the box. Rotate by re-running `github-setup.sh` and
   `gh auth login`.
2. Claude: claude.ai → Settings → sign out other sessions; `claude auth login` again.
3. ChatGPT: chatgpt.com → Settings → Security → log out of all devices; `codex login`.
4. Paperclip: `paperclipai auth revoke-current`, then `paperclipai auth login`.
5. If a secret was committed here: rotate it first (step 1–4), then rewrite history;
   a pushed secret is public the moment it lands.
