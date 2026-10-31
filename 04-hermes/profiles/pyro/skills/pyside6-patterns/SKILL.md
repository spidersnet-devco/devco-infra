---
name: pyside6-patterns
description: PySide6 patterns: workers, signals, settings, dialogs
version: 1.0.0
author: devco
license: MIT
metadata:
  hermes:
    tags: [pyside6, qt, gui, threads, signals]
---

# PySide6 patterns

## Overview
Desktop apps here (Peel and friends) are PySide6. Most bugs come from blocking the
UI thread or touching widgets from a worker. These patterns avoid both.

## When to Use
Any change under a `ui/`, `widgets/`, `gui/` package, or any file importing
`PySide6`.

## Procedure
1. **Long work never runs on the UI thread.** Batch image processing, disk scans,
   network calls go through a `QThread` + worker `QObject` (or `QThreadPool` +
   `QRunnable`). The worker emits signals; the UI slot updates widgets.
   ```python
   class Worker(QObject):
       progress = Signal(int, int)      # done, total
       finished = Signal(object)        # result
       failed = Signal(str)

       @Slot()
       def run(self):
           try:
               ...
               self.finished.emit(result)
           except Exception as e:      # noqa: BLE001 — report, don't crash the app
               self.failed.emit(str(e))
   ```
   Move the worker with `worker.moveToThread(thread)`, connect
   `thread.started -> worker.run`, and `worker.finished -> thread.quit`.
2. **Widgets are only touched from the UI thread.** If you see a widget method
   called inside a worker, that is the bug.
3. **Cancellation:** workers check a `threading.Event` (or an `is_cancelled`
   flag) between items; never `terminate()` a thread.
4. **Settings:** `QSettings` with the app's org/app name already set in `main`.
   Read with a default, write on change, never on every keystroke.
5. **Dialogs:** prefer `QMessageBox` static helpers; non-blocking progress via a
   `QProgressDialog` or an in-window progress bar driven by the worker's signal.
6. **File dialogs** remember the last directory in `QSettings`.
7. **Resources:** icons/images via the repo's existing resource mechanism (check
   for `resources.qrc` or an `assets/` loader); don't invent a second one.
8. **Testing Qt:** use `pytest-qt`'s `qtbot` if present; otherwise test the
   non-Qt logic (the worker's pure functions) directly. Always run with
   `QT_QPA_PLATFORM=offscreen`.

## Pitfalls
- `time.sleep` or a tight loop in a slot: the whole window freezes.
- Emitting a signal with a Qt object created in another thread.
- Connecting a signal twice (duplicate handlers fire twice).
- Blocking `QThread.wait()` on the UI thread at shutdown without a timeout.

## Verification
The app stays responsive during the operation (progress updates arrive), cancel
works, and tests pass offscreen.
