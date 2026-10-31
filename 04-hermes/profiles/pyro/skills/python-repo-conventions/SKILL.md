---
name: python-repo-conventions
description: Venv, tooling, layout and tests in Dev Co. Python repos
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [python, pytest, ruff, venv, conventions]
---

# Python repo conventions

## Overview
Every Python repo here follows the same shape so you never have to rediscover it.
Where a repo deviates, its own `AGENTS.md` (or `CLAUDE.md`) at the repo root wins;
read it first.

## When to Use
Any ticket touching a Python project. Pair with `devco-workflow`.

## Quick Reference
```bash
cd <repo>
python3 -m venv .venv && source .venv/bin/activate   # once per repo
pip install -e ".[dev]" || pip install -r requirements.txt
ruff check . && ruff format --check .                # lint + style
QT_QPA_PLATFORM=offscreen pytest -q                  # tests (Qt-safe)
```

## Procedure
1. Read `AGENTS.md`/`CLAUDE.md`/`README.md` at the root. Note the run command,
   the test command, and any "do not touch" areas.
2. Layout you should expect: `src/<package>/` or `<package>/`, `tests/`,
   `pyproject.toml`. Put new code next to the code it belongs with, not in a new
   top-level module, unless the ticket says so.
3. Style: ruff is the formatter and linter. Type hints on new public functions.
   f-strings. `pathlib` over `os.path`. No bare `except:`.
4. Tests: pytest, one test file per module under `tests/`, fixtures in
   `conftest.py`. Name tests `test_<behavior>` not `test_<function>`.
   Mock the filesystem and network; never hit real services in tests.
5. Logging: use the module logger (`logging.getLogger(__name__)`), never `print`,
   in library code.
6. Dependencies: adding one is a ticket question, not a decision you make.

## Pitfalls
- A test that passes only because it asserts nothing. Assert the behavior.
- Importing from `tests/` into application code.
- Editing generated files (`*_ui.py` from Qt Designer, `*.egg-info`, lockfiles).
- Forgetting `QT_QPA_PLATFORM=offscreen` on a headless box: Qt tests will hang.

## Verification
`ruff check .` clean, `pytest -q` green, and the diff only touches files the ticket
implicated.
