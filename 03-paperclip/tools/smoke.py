#!/opt/devco/venv/bin/python
"""smoke.py — headless browser smoke test for the company's web apps.

    /opt/devco/venv/bin/python /opt/devco/bin/smoke.py <url> [--out DIR]

Loads the URL at phone (390x844) and desktop (1280x800) widths, collects page
errors and console errors, flags horizontal overflow, and writes
smoke-phone.png / smoke-desktop.png into --out (default: a fresh temp dir).
Exit 0 when both viewports have no errors and no horizontal scroll, else 1.
"""
import argparse, asyncio, sys, tempfile, pathlib
from playwright.async_api import async_playwright

VIEWPORTS = (("phone", 390, 844), ("desktop", 1280, 800))

async def main(url: str, out: pathlib.Path) -> int:
    rc = 0
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for name, w, h in VIEWPORTS:
            page = await b.new_page(viewport={"width": w, "height": h})
            errors: list[str] = []
            page.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
            page.on("console", lambda m: errors.append(f"console.{m.type}: {m.text}") if m.type == "error" else None)
            page.on("requestfailed", lambda r: errors.append(f"request failed: {r.url}"))
            try:
                await page.goto(url, wait_until="load", timeout=30000)
            except Exception as e:  # noqa: BLE001
                errors.append(f"goto failed: {e}")
            await page.wait_for_timeout(1500)
            shot = out / f"smoke-{name}.png"
            await page.screenshot(path=str(shot), full_page=True)
            sx = await page.evaluate("document.documentElement.scrollWidth > window.innerWidth")
            print(f"{name}: errors={len(errors)} horizontal_scroll={sx} screenshot={shot}")
            for e in errors[:10]:
                print("   ", e)
            if errors or sx:
                rc = 1
        await b.close()
    return rc

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    out = pathlib.Path(a.out) if a.out else pathlib.Path(tempfile.mkdtemp(prefix="smoke-"))
    out.mkdir(parents=True, exist_ok=True)
    sys.exit(asyncio.run(main(a.url, out)))
