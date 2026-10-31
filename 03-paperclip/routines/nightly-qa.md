Run the QA script against every repository under /opt/devco/repos on its main branch:

    /opt/devco/bin/qa-run.sh --all-main

It prints one PASS/FAIL line per repository plus the failing sections. For every FAIL,
create a task assigned to the CEO titled "QA failure: <repo> <date>" containing the
failing section of the output verbatim (no more than 60 lines) and a one-line guess at
the cause. Do not attempt to fix anything. Do not create a task for a repo that
already has an open "QA failure: <repo>" task. Finish by posting a one-line summary on
this task: "<n> repos checked, <m> failing".
