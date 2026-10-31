---
name: web-repo-conventions
description: Working in one of the company's web repos — tooling, layout, style, tests. Use before editing HTML/CSS/JS/TS.
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [web, frontend, javascript, css, conventions]
---

# Web repo conventions

## Overview
Two kinds of web project live here: (a) single-file HTML apps with no build
step, and (b) small Node/Vite projects. Figure out which you are in before
touching anything.

## When to Use
Any ticket touching `.html`, `.css`, `.js`, `.ts`, or a `package.json`. Pair with
`devco-workflow`.

## Quick Reference
```bash
cd <repo>
ls package.json 2>/dev/null && echo "node project" || echo "single-file or static"
# node project:
npm ci && npm run lint && npm test && npm run build
# static / single-file: see browser-smoke-test skill
```

## Procedure
1. Read `AGENTS.md`/`README.md` at the root. Note the dev command and any
   "do not touch" areas.
2. **Single-file apps:** one `.html` holds markup, `<style>` and `<script>`.
   Keep it that way. State lives in `localStorage` behind a tiny versioned
   wrapper (`loadState()/saveState()` with a `schemaVersion`), so old saves
   don't crash new code. Wrap storage access in try/catch.
3. **Node projects:** follow the repo's existing lint/format config. Don't add
   ESLint/Prettier if they aren't there. Components small, named by what they
   show. No global mutable state outside the store the repo already uses.
4. **CSS:** custom properties on `:root` for colors/spacing; support
   `prefers-color-scheme: dark`; 16px side gutters on phones; no horizontal scroll.
5. **JS:** modern syntax, no jQuery unless present. Fetch with timeouts and visible
   error states. Never swallow errors silently.
6. **Accessibility:** every input has a label; buttons are `<button>`; focus is
   visible; color is never the only signal.
7. **PWA bits** (if the app has a manifest/service worker): bump the cache name on
   any change to cached files or users will keep the old version forever.

## Pitfalls
- Editing a built file (`dist/`, `*.min.js`) instead of its source.
- Breaking the single-file promise by adding external files.
- Forgetting the service-worker cache bump (the number-one "my fix isn't
  showing up" cause).
- Layout that only works at 1920px wide.

## Verification
Lint/tests/build green where they exist; the page renders and works at 390px and
1280px wide in the headless browser (see `browser-smoke-test`).
