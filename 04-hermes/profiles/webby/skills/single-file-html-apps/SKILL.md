---
name: single-file-html-apps
description: Patterns for self-contained single-file HTML apps
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [html, single-file, localstorage, pwa, offline]
---

# Single-file HTML apps

## Overview
Several tools here are deliberately one `.html` file: open it, it works, no server,
no build. These apps get big, so a consistent internal structure is what keeps
them maintainable.

## When to Use
Any ticket on an app whose whole UI is one HTML file (or an HTML file plus an
optional `manifest.json`/`sw.js`).

## Procedure
1. **Keep the file's section order**: `<head>` meta + `<style>`; markup;
   `<script>` in this order: constants → state + storage → pure helpers →
   rendering → event wiring → init. Add code to the matching section; don't append
   to the end.
2. **State is one object** (`state`), mutated only through a few functions, and
   rendered by one `render()` call. No scattered DOM writes.
3. **Storage** goes through a single pair:
   ```js
   const STORE_KEY = 'app-name:v2';
   function loadState() { try { return migrate(JSON.parse(localStorage.getItem(STORE_KEY)) || {}); } catch { return defaults(); } }
   function saveState() { try { localStorage.setItem(STORE_KEY, JSON.stringify(state)); } catch {} }
   ```
   When the schema changes, bump the key's version suffix and add a `migrate()`
   branch for the old shape. Never silently drop a user's data.
4. **Import/export**: every app that stores anything gets an Export (download
   JSON) and Import (file picker) button. Users lose localStorage; this is the
   backup story.
5. **Large text/lore/content** stays in the file but in a `<script type="application/json" id="...">`
   block or a template literal, not interleaved with logic.
6. **Offline/PWA**: if there is a service worker, cache the HTML only, bump
   `CACHE_NAME` on every change, and call `skipWaiting()` + `clients.claim()`.
7. **No external dependencies.** If something truly needs a library, inline a
   pinned minified copy with a comment naming the version; ask first.

## Pitfalls
- `JSON.parse` on corrupted storage without try/catch (app dead on load).
- Rendering inside loops that also mutate `state` (infinite re-render).
- Growing the file past what one agent can read in a turn: if it is over ~4,000
  lines, say so on the ticket; splitting is a board decision.

## Verification
Open in the headless browser (see `browser-smoke-test`): no console errors on
load, state survives reload, export/import round-trips, works at 390px width.
