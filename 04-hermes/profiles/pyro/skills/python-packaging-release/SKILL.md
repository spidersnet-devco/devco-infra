---
name: python-packaging-release
description: Cutting a release of a Python/PySide6 app — version bump, changelog, PyInstaller build, tag. Use when a ticket says release, build, package, installer, or version.
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [release, pyinstaller, packaging, versioning, changelog]
---

# Packaging and release

## Overview
Releases are boring on purpose: bump, changelog, build, smoke-test, tag. The
board decides *when*; you make it mechanical.

## When to Use
Tickets about versions, builds, installers, release notes, or "make a build I can
hand to someone".

## Procedure
1. **Find the single source of version truth**: `pyproject.toml` `[project] version`,
   or `<package>/__init__.py` `__version__`. There must be exactly one; if there
   are two, make them agree and note it on the ticket.
2. **Bump** per the ticket (patch for fixes, minor for features). Never bump major
   without the board saying so.
3. **Changelog**: add a section at the top of `CHANGELOG.md` (create it if missing)
   with the version, the date, and 3–10 bullet lines in user language
   ("Batch export no longer skips the last file"), not commit messages.
4. **Build** with the repo's existing spec if there is one:
   ```bash
   source .venv/bin/activate
   pip install -U pyinstaller
   pyinstaller --noconfirm <app>.spec      # or the build script the README names
   ```
   If there is no spec, do not invent packaging options; ask on the ticket.
   Windows builds are produced on the board's Windows machine, not here. Your job
   on Linux is to confirm the spec still builds and the entry point runs:
   ```bash
   QT_QPA_PLATFORM=offscreen dist/<app>/<app> --version
   ```
5. **Tag** only after QA passes and the board approves the release ticket:
   ```bash
   git tag -a v<version> -m "v<version>" && git push origin v<version>
   ```
6. Hand back with the version, the changelog section, and the build log tail.

## Pitfalls
- Committing `build/` or `dist/`. They belong in `.gitignore`.
- Forgetting Qt plugins/assets in the spec (the build runs but the window is
  blank or icons are missing). Compare against the last working spec in git history.
- Bumping the version in the changelog but not in code, or vice versa.

## Verification
`pip show <package>` (or `--version`) prints the new version, CHANGELOG has the
section, build completes, tag exists only if the board approved.
