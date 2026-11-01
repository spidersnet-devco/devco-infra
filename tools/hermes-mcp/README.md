# hermes-mcp — operate the box from a Claude chat on your PC

A ~150-line MCP server (Python standard library only) that the Claude desktop app runs
on the board's PC. It exposes two tools — `hermes_run` (a command on the box over SSH)
and `hermes_put` (write a file on the box) — so a Claude session on that PC can work
on hermes directly, LAN-only, with nothing exposed to the internet. The key stays on
the PC. Any Claude session on that PC gets the same power as your SSH login, so treat
the PC like the box.

Setup (Windows, once):

1. Put `hermes_mcp.py` somewhere stable, e.g. `Documents\devco\`.
2. Make a key for it (Command Prompt): `ssh-keygen -t ed25519 -N "" -f %USERPROFILE%\Documents\devco\id_ed25519_devco`
   and authorize it on the box (PuTTY):
   `mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '<contents of id_ed25519_devco.pub>' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys`
3. Test from the PC: `ssh -i %USERPROFILE%\Documents\devco\id_ed25519_devco geoff@hermes.local hostname` → `hermes`.
4. Claude desktop app → Settings → Developer → Edit Config, add under `mcpServers`:
   ```json
   "hermes": {
     "command": "C:\\Users\\<you>\\miniconda3\\python.exe",
     "args": ["C:\\Users\\<you>\\Documents\\devco\\hermes_mcp.py"],
     "env": { "HERMES_SSH_HOST": "hermes.local", "HERMES_SSH_USER": "geoff",
              "HERMES_SSH_KEY": "C:\\Users\\<you>\\Documents\\devco\\id_ed25519_devco" }
   }
   ```
   Restart the app. The tools appear in chats on that PC as `hermes_run` / `hermes_put`.

Notes: `sudo` needs a password, so root-only commands fail by design (unlock/lockdown
stay yours). Output is capped at ~120 KB per stream; long commands take a `timeout`.
