---
name: status
description: Show where every Bondsmith task stands, from any session in the home repo, without touching anything. Prints the board's live rows with each worker session's current state and the age of its report. Usage /bondsmith:status.
allowed-tools: Read, Bash(command claude agents --json), Bash(date *)
---

# Bondsmith status

Run in the home repo. Read only: never write a file, message a session, or start, resume or stop one. This works whether or not an orchestrator is running.

1. Read `orchestrator/board.md`. If it does not exist, say to run `/bondsmith:setup` and stop.
2. Run `command claude agents --json` once. Match each Live row to the entry whose `name` is the task id.
3. For each Live row, run `date -r orchestrator/tasks/<task-id>/report.md '+%Y-%m-%d %H:%M:%S'` (no report yet if it fails), and `date '+%Y-%m-%d %H:%M:%S'` once for now.
4. Print one table, Live rows only: task, state, round, waiting on, next, session (the entry's `state`, `idle` in place of `blocked` when it has no `waitingFor`, or `gone` if none matches), report (its time and how long ago), notes. Then one line: how many Finished rows there are.
5. Under the table, one line per task that needs the user, in this order:
   - session `blocked` with `waitingFor` set: `claude attach <task-id>` to answer its prompt;
   - board `waiting on` `user`: the row's `next`;
   - report newer than the row's `updated`: the orchestrator has not processed it yet;
   - board `running` but session `gone`: the orchestrator resumes it at its next start or turn.
