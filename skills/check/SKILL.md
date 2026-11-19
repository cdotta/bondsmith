---
name: check
description: Run one Bondsmith check round on a task by hand, or as part of /bondsmith:orchestrate when a worker reports ready-for-check. Usage /bondsmith:check <task-id>. Spawns the checker subagent, writes check.md and updates the board.
allowed-tools: Bash(command claude agents --json), Bash(date *)
---

# Bondsmith check round

Task id: `$ARGUMENTS`. Run in the home repo; all paths below are under its `orchestrator/` directory, and you pass them as absolute paths.

1. Read `orchestrator/config.md` (Workers row: `checker model`, `max check rounds`, `orchestrator name`) and `orchestrator/board.md`. Find the task's row. If there is none, say so and stop.
   If `command claude agents --json` lists a session whose `name` is the `orchestrator name` and whose `sessionId` is not `${CLAUDE_SESSION_ID}` (this session), the orchestrator owns the board: tell the user to run the check in that session, and stop.
2. Spawn the `bondsmith:checker` agent with model = `checker model` and a prompt that holds only these three absolute paths and nothing else, no opinion of the work:
   - brief: `<home>/orchestrator/tasks/<task-id>/brief.md`
   - report: `<home>/orchestrator/tasks/<task-id>/report.md`
   - worktree: the row's `worktree`
   Wait for its result. Do not end your turn, reply, or do anything else until it returns.
3. Let `n` = the row's `round` + 1. Write `orchestrator/tasks/<task-id>/check.md`, replacing any old one:
   - line 1: `Verdict: pass` or `Verdict: fail` (fail if any item failed)
   - line 2: `Round: <n>`
   - then one line per item from the checker: `- pass: <item>`, `- fail: <item>: <reason>` or `- ask-first: <item>: <where>`
   - then, if the checker returned notes after its verdict, a blank line, `## Notes`, and the notes as it wrote them
4. Update the task's board row. Set `updated` to the current date and time (`date '+%Y-%m-%d %H:%M:%S'`), taken now, before step 5 messages the worker.
   - Any `ask-first` line, whatever the round: `round` `n`, `state` `needs-user`, `waiting on` `user`, `next` `decide ask-first item`. Another round cannot fix work the user has not agreed to.
   - All pass: `round` `n`, `state` `validated`, `waiting on` `user`, `next` `merge PR`.
   - Any fail, and `n` < `max check rounds`: `round` `n`, `state` `running`, `waiting on` `worker`, `next` `fix check round <n>`.
   - Any fail, and `n` ≥ `max check rounds`: `round` `n`, `state` `needs-user`, `waiting on` `user`, `next` `decide after <n> failed checks`.
5. Then:
   - `validated`: tell the user in two lines: the task passed, and the PR link from the report if there is one.
   - `running`: send the worker session (its name is the task id) one message: `Check failed. Fix what <absolute path to check.md> lists, and every other instance of the same kind, then report again.` If `command claude agents --json` shows no live session with that name, run `cd <worktree> && command claude --resume <session> --bg "<the same message>"; cd <home>` as one command (not in a `( )` subshell) with the row's `session`. If that fails too, keep `state` `running`, set `waiting on` `user` and `next` `resume <task-id>`, and tell the user.
   - `needs-user`: show the user the `fail` and `ask-first` lines of `check.md` and ask what to do. For an `ask-first` line, ask whether to keep the change.
