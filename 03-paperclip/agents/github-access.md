# GitHub access model for the company

One human, one bot, one org.

| Identity | GitHub account | Used for |
|---|---|---|
| You (the board) | `SpiderPharaoh` | Owner of the org. Creates repos, reviews, **merges**. Nothing of yours is ever on the box. |
| The agents | `spidersnet-devco-bot` | Member of the org. Pushes branches, opens PRs, comments. Lives on the box via SSH key + `gh` login. |

## One-time setup (browser, as you)

1. Create the bot account at github.com/signup with `devco-bot@spidersnet.net`, turn on 2FA for it.
2. Org → **People → Invite member** → `spidersnet-devco-bot` → role **Member**. Accept the invite logged in as the bot.
3. Org → **Teams → New team** → name `agents`. Add the bot as a member.
4. For each project repo: repo **Settings → Collaborators and teams → Add teams** → `agents` → role **Write**.
   (New repos: do this when you create them. The bot can't push until you do.)
5. Logged in as the bot: Settings → Emails → tick **Keep my email addresses private**, copy the
   `...@users.noreply.github.com` address into `GITHUB_BOT_NOREPLY` in `/opt/devco/devco.env`.

Then on the box: `bash 03-paperclip/github-setup.sh` and its three printed steps.

## What the roles mean here

- **Write** lets the bot push branches and open PRs. It also *technically* allows pushing to
  `main` on the Free plan (no protected branches on private repos). The agents' instructions
  forbid it; if one ever does it anyway, upgrade the org to Team and turn on branch protection.
- The bot is never an org **Owner** and never an **Admin** on a repo. It cannot delete repos,
  change settings, or add collaborators.
- `gh` on the box is logged in as the bot with the default `repo` scope, which is what
  `gh pr create`, `gh pr view`, and `gh issue` need. No org-admin scopes.

## Revoking the agents in one click

Org → People → `spidersnet-devco-bot` → Remove from organization. Every agent loses push
and PR access instantly; nothing on your account changes.

## Your own notifications

Add `github@spidersnet.net` as a verified email on your account, then Settings →
Notifications → **Custom routing** → route `spidersnet-devco` to it. Every "review
requested" and "PR ready" lands in one Proton folder.
