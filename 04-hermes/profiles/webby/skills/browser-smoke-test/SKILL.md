---
name: browser-smoke-test
description: Verify a web change in headless Chromium before hand-back
version: 2.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [testing, playwright, headless, screenshot, web]
---

# Browser smoke test

## Overview
"It parses" is not "it works". Every web hand-back includes a headless-browser
check at phone and desktop width, with screenshots attached to the task.

## When to Use
The last step of any ticket touching HTML/CSS/JS, before `/opt/devco/bin/qa-run.sh .`.

## Quick Reference
The script and its browser are already installed on this box:

```bash
/opt/devco/venv/bin/python /opt/devco/bin/smoke.py <url> [--out DIR]
```

If it reports that Chromium is missing: `/opt/devco/venv/bin/playwright install chromium`
(no sudo needed; the system libraries were installed at setup).

## Procedure
1. Serve the files if the app needs http (service workers, `fetch` of local files):
   ```bash
   python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 & echo $! > "$(mktemp -u /tmp/httpd.XXXX).pid"
   ```
   Pure single-file apps can be opened via `file:///absolute/path/app.html`.
2. Run the smoke test and keep its output:
   ```bash
   out="$(mktemp -d)"
   /opt/devco/venv/bin/python /opt/devco/bin/smoke.py http://127.0.0.1:8765/index.html --out "$out"
   ```
   It prints one line per viewport: `errors=<n> horizontal_scroll=<bool>` plus the
   first errors, and exits non-zero when anything is wrong.
3. Exercise the ticket's feature if it can be scripted (a small Playwright snippet
   using the same interpreter, or a second `smoke.py` call on the feature's URL) and
   screenshot the result. Keep it to the feature; this is a smoke test, not a suite.
4. Attach `$out/smoke-phone.png` and `$out/smoke-desktop.png` to the task, and paste
   the `errors=` lines into the PR's QA section.
5. Kill the http server you started (`kill "$(cat /tmp/httpd.*.pid)"`).

## Pitfalls
- Testing only at desktop width.
- Ignoring console errors because "the page looks fine".
- Leaving the http.server running (ports pile up).
- Writing fixed filenames in /tmp (two agents can run at once; use `mktemp`).

## Verification
Both viewports: `errors=0`, `horizontal_scroll=False`, screenshots attached.
