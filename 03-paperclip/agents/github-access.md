# GitHub access model for the company

One human, one bot, one org. GitHub's terms allow one machine account per person, so
every agent shares the bot; the review process is designed around that.

| Identity | GitHub account | Used for |
|---|---|---|
| You (the board) | `SpiderPharaoh` | Owner of the org. Creates repos, approves, **merges**. Nothing of yours is ever on the box. |
| The agents | `spidersnet-devco-bot` | Member of the org. Pushes branches, opens PRs, comments, labels. Lives on the box via SSH key + `gh` login. |

## One-time setup (browser, as you)

1. Create the bot account at github.com/signup with `devco-bot@spidersnet.net`, turn on 2FA for it.
2. Logged in as the bot: Settings → Emails → tick **Keep my email addresses private** and
   **Block command line pushes that expose my email**; copy the
   `<id>+spidersnet-devco-bot@users.noreply.github.com` address into `GITHUB_BOT_NOREPLY`
   in `/opt/devco/devco.env`.
3. Org → **People → Invite member** → `spidersnet-devco-bot` → role **Member**. Accept the invite logged in as the bot.
4. Org → **Teams → New team** → name `agents`. Add the bot as a member.
5. For each project repo: repo **Settings → Collaborators and teams → Add teams** → `agents` → role **Write**.
   (`clone-project.sh` reminds you when the bot can't push. New repos: do this when you create them.)

Then on the box: `bash 03-paperclip/github-setup.sh` (the unattended install already
generated the key; this step sets the git identity and prints the two login commands).

## What the roles mean here

- **Write** lets the bot push branches, open PRs, comment, and add labels. It also
  *technically* allows pushing to `main` on the Free plan (no branch protection on
  private repos). The agents' instructions forbid it, and `03-paperclip/lockdown.sh`
  adds a local pre-push hook on every clone that refuses pushes to `main`. Make a
  repo **public** to get free rulesets (`devco-infra` already is): Settings → Rules →
  Rulesets → New branch ruleset → target `main` → "Require a pull request before merging".
  Or upgrade the org to Team ($4/seat) for protection on private repos.
- The bot is never an org **Owner** and never an **Admin** on a repo. It cannot delete
  repos, change settings, or add collaborators.
- `gh` on the box is logged in as the bot with the default scopes `repo`, `read:org`,
  `gist`; that covers `gh pr create/diff/review --comment/edit --add-label`,
  `gh search prs` and `gh repo list`. No org-admin scopes.

## Reviews with one shared identity

GitHub refuses "Pull request authors cannot approve their own pull requests", and the
Reviewer *is* the author as far as GitHub knows. So the Reviewer posts its verdict as a
**review comment** plus a label (`reviewer-approved` or `changes-requested`), and the
formal approval is Paperclip's review stage plus **you merging**. `clone-project.sh`
creates the two labels on each repo.

## Revoking the agents in one click

Org → People → `spidersnet-devco-bot` → Remove from organization. Every agent loses
push and PR access instantly; nothing on your account changes. To also kill the key:
bot account → Settings → SSH keys → delete the `hermes` key, and on the box
`gh auth logout`.

## Your own notifications

Add `github@spidersnet.net` as a verified email on your account, then Settings →
Notifications → **Custom routing** → route `spidersnet-devco` to it. Every "review
requested" and "PR ready" lands in one Proton folder.
