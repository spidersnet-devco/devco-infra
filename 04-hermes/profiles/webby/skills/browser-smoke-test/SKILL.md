---
name: browser-smoke-test
description: Verify a web change in a real headless browser (Playwright/Chromium) — load, console errors, screenshot at phone and desktop width. Use before handing back any web ticket.
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [testing, playwright, headless, screenshot, web]
---

# Browser smoke test

## Overview
"It parses" is not "it works". Every web hand-back includes a headless-browser
check with a screenshot attached to the ticket.

## When to Use
The last step of any ticket touching HTML/CSS/JS, before `/opt/devco/qa-run.sh`.

## Quick Reference
One-time setup on this box (ask ops if it fails):
```bash
python3 -m pip install --user playwright && python3 -m playwright install chromium
```

## Procedure
1. Serve the files if the app needs http (service workers, fetch of local files):
   ```bash
   cd <repo> && python3 -m http.server 8765 >/dev/null 2>&1 &
   ```
   Pure single-file apps can be opened via `file://`.
2. Run the smoke script (save as `/opt/devco/smoke.py` once if it's not there):
   ```python
   import sys, asyncio
   from playwright.async_api import async_playwright
   url = sys.argv[1]
   async def main():
       async with async_playwright() as p:
           b = await p.chromium.launch()
           for name, w, h in (("phone", 390, 844), ("desktop", 1280, 800)):
               page = await b.new_page(viewport={"width": w, "height": h})
               errors = []
               page.on("pageerror", lambda e: errors.append(str(e)))
               page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
               await page.goto(url, wait_until="load")
               await page.wait_for_timeout(1500)
               await page.screenshot(path=f"/tmp/smoke-{name}.png", full_page=True)
               sx = await page.evaluate("document.documentElement.scrollWidth > window.innerWidth")
               print(f"{name}: errors={len(errors)} horizontal_scroll={sx}")
               for e in errors[:10]: print("   ", e)
           await b.close()
   asyncio.run(main())
   ```
   ```bash
   python3 /opt/devco/smoke.py http://127.0.0.1:8765/index.html   # or file:///path/app.html
   ```
3. Exercise the ticket's feature if it can be scripted (click the button, fill
   the form) and screenshot the result. Keep it to the feature; this is a smoke
   test, not a suite.
4. Attach `/tmp/smoke-phone.png` and `/tmp/smoke-desktop.png` to the ticket as
   artifacts, and paste the `errors=` lines into the hand-back.
5. Kill the http server you started.

## Pitfalls
- Testing only at desktop width.
- Ignoring console errors because "the page looks fine".
- Leaving the http.server running (ports pile up).

## Verification
Both viewports: `errors=0`, `horizontal_scroll=False`, screenshots attached.
