#!/usr/bin/env python3
"""hermes_mcp.py — a tiny MCP server that runs commands on the hermes box over SSH.

Runs on the board's PC under the Claude desktop app (a "local MCP server"), so a Claude
session on that PC can operate the box from the chat. Python standard library only; no
third-party code holds the key.

Tools
  hermes_run   run a shell command on the box (bash -lc), return stdout/stderr/exit code
  hermes_put   write a text file on the box (content goes over stdin, nothing is quoted)

Configuration (environment, set in the desktop app's MCP config):
  HERMES_SSH_HOST   default hermes.local
  HERMES_SSH_USER   default geoff
  HERMES_SSH_PORT   default 22
  HERMES_SSH_KEY    path to the private key (required)
  HERMES_SSH_BIN    default "ssh" (Windows: C:\\Windows\\System32\\OpenSSH\\ssh.exe is on PATH)

Protocol: MCP over stdio, newline-delimited JSON-RPC 2.0. Only stdout carries protocol
messages; logs go to stderr.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

HOST = os.environ.get("HERMES_SSH_HOST", "hermes.local")
USER = os.environ.get("HERMES_SSH_USER", "geoff")
PORT = os.environ.get("HERMES_SSH_PORT", "22")
KEY = os.environ.get("HERMES_SSH_KEY", "")
SSH = os.environ.get("HERMES_SSH_BIN", "ssh")
MAX_TIMEOUT = 900
MAX_OUTPUT = 120_000  # characters per stream returned to the model

TOOLS = [
    {
        "name": "hermes_run",
        "description": (
            f"Run a shell command on the hermes box as {USER}@{HOST} (bash -lc). Returns stdout, "
            "stderr and the exit code. Long or interactive commands are not supported; use a "
            "timeout for anything slow. sudo needs a password, so commands that require root fail."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "The command line to run with bash -lc."},
                "timeout": {
                    "type": "integer",
                    "description": f"Seconds before the command is killed (default 120, max {MAX_TIMEOUT}).",
                },
                "cwd": {"type": "string", "description": "Directory to cd into first (optional)."},
            },
            "required": ["command"],
        },
    },
    {
        "name": "hermes_put",
        "description": (
            f"Write a text file on the hermes box as {USER}@{HOST}. The content is sent over "
            "stdin, so any text is safe. Parent directories are created. Existing files are "
            "overwritten."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute path, or relative to the home directory."},
                "content": {"type": "string", "description": "The full file content."},
                "mode": {"type": "string", "description": "chmod mode such as 0755 (optional)."},
            },
            "required": ["path", "content"],
        },
    },
]


def log(msg: str) -> None:
    sys.stderr.write(f"[hermes_mcp] {msg}\n")
    sys.stderr.flush()


def ssh_base() -> list[str]:
    args = [SSH, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30", "-p", PORT]
    if KEY:
        args += ["-i", KEY]
    args.append(f"{USER}@{HOST}")
    return args


def clip(s: str) -> str:
    if len(s) <= MAX_OUTPUT:
        return s
    return s[: MAX_OUTPUT // 2] + f"\n…[{len(s) - MAX_OUTPUT} characters omitted]…\n" + s[-MAX_OUTPUT // 2 :]


def run_remote(remote_cmd: str, timeout: int, stdin_text: str | None = None) -> dict:
    try:
        proc = subprocess.run(
            ssh_base() + [remote_cmd],
            input=stdin_text,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or b"").decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        err = (exc.stderr or b"").decode("utf-8", "replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        return {"ok": False, "exit": None, "stdout": clip(out), "stderr": clip(err), "error": f"timed out after {timeout}s"}
    except FileNotFoundError:
        return {"ok": False, "exit": None, "stdout": "", "stderr": "", "error": f"ssh binary not found: {SSH}"}
    return {"ok": proc.returncode == 0, "exit": proc.returncode, "stdout": clip(proc.stdout), "stderr": clip(proc.stderr)}


def bash_quote(s: str) -> str:
    return "'" + s.replace("'", "'\"'\"'") + "'"


def path_quote(p: str) -> str:
    """Quote a path for bash, letting a leading ~/ mean the remote home directory."""
    if p == "~":
        return '"$HOME"'
    if p.startswith("~/"):
        return '"$HOME"/' + bash_quote(p[2:])
    return bash_quote(p)


def tool_run(args: dict) -> dict:
    command = str(args.get("command", "")).strip()
    if not command:
        return {"ok": False, "error": "command is required"}
    timeout = int(args.get("timeout") or 120)
    timeout = max(5, min(timeout, MAX_TIMEOUT))
    cwd = args.get("cwd")
    script = command if not cwd else f"cd {path_quote(str(cwd))} && {command}"
    remote = f"bash -lc {bash_quote(script)}"
    res = run_remote(remote, timeout + 5)
    return res


def tool_put(args: dict) -> dict:
    path = str(args.get("path", "")).strip()
    content = args.get("content", "")
    mode = str(args.get("mode") or "").strip()
    if not path:
        return {"ok": False, "error": "path is required"}
    if not isinstance(content, str):
        return {"ok": False, "error": "content must be a string"}
    q = path_quote(path)
    script = f"mkdir -p \"$(dirname {q})\" && cat > {q}"
    if mode:
        script += f" && chmod {bash_quote(mode)} {q}"
    script += f" && wc -c < {q}"
    res = run_remote(f"bash -lc {bash_quote(script)}", 60, stdin_text=content)
    if res.get("ok"):
        res["stdout"] = f"wrote {res['stdout'].strip()} bytes to {path}"
    return res


def format_result(res: dict) -> dict:
    parts = []
    if res.get("error"):
        parts.append(f"error: {res['error']}")
    if res.get("exit") is not None:
        parts.append(f"exit: {res['exit']}")
    if res.get("stdout"):
        parts.append("stdout:\n" + res["stdout"].rstrip("\n"))
    if res.get("stderr"):
        parts.append("stderr:\n" + res["stderr"].rstrip("\n"))
    text = "\n".join(parts) if parts else "(no output)"
    return {"content": [{"type": "text", "text": text}], "isError": not res.get("ok", False)}


def handle(msg: dict) -> dict | None:
    method = msg.get("method")
    mid = msg.get("id")
    params = msg.get("params") or {}
    if method == "initialize":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": params.get("protocolVersion") or "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "hermes-mcp", "version": "1.0.0"},
        }}
    if method in ("notifications/initialized", "notifications/cancelled"):
        return None
    if method == "ping":
        return {"jsonrpc": "2.0", "id": mid, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}
    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        if name == "hermes_run":
            return {"jsonrpc": "2.0", "id": mid, "result": format_result(tool_run(args))}
        if name == "hermes_put":
            return {"jsonrpc": "2.0", "id": mid, "result": format_result(tool_put(args))}
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": f"unknown tool {name}"}}
    if mid is None:
        return None  # unknown notification: ignore
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"method not found: {method}"}}


def main() -> None:
    if not KEY:
        log("HERMES_SSH_KEY is not set; ssh will rely on the default key/agent")
    log(f"serving {USER}@{HOST}:{PORT}")
    stdin = sys.stdin.buffer
    out = sys.stdout.buffer
    while True:
        line = stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line.decode("utf-8"))
        except Exception as exc:  # noqa: BLE001
            log(f"bad json: {exc}")
            continue
        try:
            reply = handle(msg)
        except Exception as exc:  # noqa: BLE001
            reply = {"jsonrpc": "2.0", "id": msg.get("id"), "error": {"code": -32603, "message": str(exc)}}
        if reply is not None:
            out.write((json.dumps(reply) + "\n").encode("utf-8"))
            out.flush()


if __name__ == "__main__":
    main()
