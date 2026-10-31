---
name: devco-workflow
description: How every engineering ticket at Spidersnet Dev Co. is worked, from checkout to hand-back. Use on EVERY coding task that arrives from Paperclip.
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [workflow, git, qa, paperclip, handback]
---

# Dev Co. ticket workflow

## Overview
One ticket = one branch = one hand-back with evidence. The Reviewer (Codex) and the
Watchdog re-check everything you claim, so claims without evidence get bounced.

## When to Use
Any task that changes files in a repository under /opt/devco/repos. Load this first,
then the skill for the repo's technology.

## Procedure
1. **Read the ticket twice.** Find: repo path, branch name, the "done" checklist,
   files named, and the "do not touch" list. If any of the first three is missing,
   stop and ask on the ticket; do not guess.
2. **Check out cleanly.**
   ```bash
   cd <repo> && git fetch -q && git status --porcelain
   ```
   If the tree is dirty, stop and report it. Then:
   ```bash
   git checkout main && git pull -q --ff-only
   git checkout -b <branch>      # or `git checkout <branch>` if it exists
   ```
3. **Understand before editing.** Read the files the ticket names and their direct
   imports/callers. Do not crawl the whole repo. If understanding requires more
   than ~10 files, say so on the ticket; that is a sign the task is above your rung.
4. **Make the smallest change that satisfies the checklist.** No drive-by refactors,
   no formatting sweeps, no new dependencies without asking.
5. **Add or update tests** for what you changed. A fix without a test that fails
   before and passes after is not done.
6. **Run QA** and keep the output:
   ```bash
   /opt/devco/qa-run.sh <repo> <branch> 2>&1 | tail -n 80
   ```
   Fix what it reports. If you cannot get to `QA: PASS` after two attempts, stop.
7. **Commit and push** with a message that starts with the ticket id:
   ```bash
   git add -A && git commit -m "<ticket-id>: <what changed>" && git push -u origin <branch>
   ```
8. **Open the pull request.** The PR is the hand-back; the Reviewer and the board
   read it on GitHub, not in the terminal.
   ```bash
   gh pr create --base main --head <branch> \
     --title "<ticket-id>: <what changed>" \
     --body-file /tmp/pr-body.md
   ```
   Write `/tmp/pr-body.md` first, in this exact shape:
   ```
   ## Ticket
   <ticket-id> — <one-line title>

   ## Summary
   one or two sentences

   ## Changed
   - file list

   ## QA
   PASS|FAIL — last 15 lines of /opt/devco/qa-run.sh output in a code block

   ## Unsure
   anything you are not confident about (or "nothing")
   ```
   `gh pr create` prints the PR URL. If it fails with a permissions error, say so on
   the ticket; the bot may not have Write on this repo yet. Never work around it by
   pushing to main.
9. **Hand back on the ticket**: paste the PR URL plus the Summary and QA lines, then
   mark the task done / ready for review.

## Pitfalls
- Never commit to main. Never force-push. Never rewrite history on a shared branch.
- Never delete tests to make QA pass.
- Never leave debugging prints or commented-out code.
- If the ticket is outside your field (see SOUL.md), hand it back to the CEO
  immediately with one sentence saying why. That is a success, not a failure.
- Secrets: never paste a token, key or password into a ticket, log or commit.

## Verification
A PR exists with all five sections filled, QA says PASS, `git status` is clean, and the
ticket carries the PR URL.
