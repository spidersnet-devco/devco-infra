---
name: devco-workflow
description: How every Dev Co. ticket is worked, checkout to hand-back
version: 2.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [workflow, git, qa, paperclip, handback]
---

# Dev Co. ticket workflow

## Overview
One ticket = one branch = one pull request with evidence. The Reviewer (Codex) and
the Watchdog re-check everything you claim, so claims without evidence get bounced.
Load this on EVERY coding task that arrives from Paperclip, then the skill for the
repo's technology.

## Vocabulary
- **ticket-id**: the task's identifier shown in Paperclip, e.g. `SDC-42`. It is in the
  task title/URL you were given. Use it in the branch name, commits and PR title.
- **branch**: `devco/<ticket-id>-<short-slug>`, unless the ticket names one.
- **repo**: your working directory. Paperclip starts you in the project's checkout
  (or an isolated worktree of it). Do not cd to another repository.

## Procedure
1. **Read the ticket twice.** Find: the "Done means" checklist, files named, the
   "do not touch" list, and the branch. If the checklist is missing, stop and ask on
   the task; do not guess.
2. **Check the tree.**
   ```bash
   git status --porcelain && git fetch -q origin
   ```
   If the tree is dirty with changes that are not yours, stop and report it on the
   task (someone else's work is here). Then:
   ```bash
   git checkout -q main && git pull -q --ff-only
   git checkout -b <branch>          # or: git checkout <branch>  if it already exists
   ```
   (In an isolated worktree you are already on the right branch; skip this.)
3. **Understand before editing.** Read the files the ticket names and their direct
   imports/callers. Do not crawl the whole repo. If understanding needs more than
   ~10 files, say so on the task; that is a sign the ticket is above your rung.
4. **Make the smallest change that satisfies the checklist.** No drive-by refactors,
   no formatting sweeps, no new dependencies without asking.
5. **Add or update tests** for what you changed. A fix without a test that fails
   before and passes after is not done.
6. **Run QA** and keep the output:
   ```bash
   /opt/devco/bin/qa-run.sh . 2>&1 | tail -n 80
   ```
   Fix what it reports. If you cannot get to `QA: PASS` after two honest fixes, stop:
   write what you tried on the task and set it to blocked. The CEO escalates.
7. **Commit and push**, message starting with the ticket-id:
   ```bash
   git add -A && git commit -m "<ticket-id>: <what changed>" && git push -u origin <branch>
   ```
8. **Open the pull request.** The PR is the hand-back; the Reviewer and the board read
   it on GitHub, not in the terminal. Write the body to a temp file first:
   ```bash
   body="$(mktemp)"
   cat > "$body" <<'MD'
   ## Ticket
   <ticket-id> — <one-line title>

   ## Summary
   one or two sentences

   ## Changed
   - file list

   ## QA
   PASS|FAIL — last 15 lines of qa-run.sh output in a code block

   ## Unsure
   anything you are not confident about (or "nothing")
   MD
   gh pr create --base main --head <branch> --title "<ticket-id>: <what changed>" --body-file "$body"
   ```
   `gh pr create` prints the PR URL. If it fails with a permissions error, say so on
   the task; the bot may not have Write on this repo yet. Never work around it by
   pushing to main.
9. **Hand back on the task**: a comment with the PR URL, the Summary and the QA line,
   then set the task status to **in_review** (the Paperclip API guidance in your
   system prompt shows the exact `curl` with `$PAPERCLIP_API_URL`, `$PAPERCLIP_API_KEY`,
   `$PAPERCLIP_TASK_ID`). Never hard-code those values or paste the key anywhere.

## Pitfalls
- Never commit to main. Never force-push. Never rewrite history on a shared branch.
- Never delete or skip tests to make QA pass.
- Never leave debugging prints or commented-out code.
- If the ticket is outside your field (see SOUL.md), hand it back to the CEO at once
  with one sentence saying why. That is a success, not a failure.
- Secrets: never paste a token, key or password into a task, log or commit.
- You get ONE attempt per ticket (with up to two QA fix rounds inside it). If the
  Reviewer sends the PR back, fix exactly the numbered items and nothing else.

## Verification
A PR exists with all five sections filled, QA says PASS, `git status` is clean, and
the task is in review with the PR URL in a comment.
