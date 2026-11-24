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
   In the same turn, so they run in parallel with the checker, spawn one `general-purpose` agent with model = `checker model` for each step on the brief's `Review steps:` line marked ` (independent)`. Its prompt is this text and nothing else, with the three paths and the step's name without the marker filled in:

   ````text
   You run one review step for a Bondsmith check round, independently of the worker who did the task.
   Step: <step>
   Brief: <brief path>
   Report: <report path>
   Worktree: <worktree path>

   Read the brief and the report. The base is the `Base:` line under "Facts and decisions" in the brief.
   If the report has a PR link, run the step on that PR; if the PR's `headRefOid` (`gh pr view <link> --json headRefOid`)
   is not `git -C <worktree path> rev-parse HEAD`, the step did not run as written: say so and stop. If there is no PR link, cut a detached worktree of your own
   (`git -C <worktree path> worktree add --detach <new empty temp dir> HEAD`), run the step there on
   `<base>...HEAD`, and remove it afterwards (`git -C <worktree path> worktree remove --force <that dir>`).

   Rules, whatever the step says:
   - Post nothing anywhere: no PR comment or review, no issue, no message.
   - Change no file in the task's worktree. Commit, push or switch branches nowhere.
   - Run no full test suite.
   When the step asks for one of these, skip that part and name it under "Skipped by the rules"; that alone does not make "Ran as written" a no.

   With a PR, read its body (`gh pr view <link> --json body`). Return only:
   Ran as written: yes | no: <what did not run, and why>
   Skipped by the rules: <parts, or none>
   Severities: <the step's own scale, highest first>
   Findings:
   - <severity>: <finding> (<file>:<line>) declared | not declared
   "declared" means the PR body already names the finding as known or left out; without a PR, nothing is. Write "Findings: none" when there are none.
   ````

   Wait for every result. Do not end your turn, reply, or do anything else until all of them return.
3. Let `n` = the row's `round` + 1. Write `orchestrator/tasks/<task-id>/check.md`, replacing any old one:
   - line 1: `Verdict: pass` or `Verdict: fail` (fail if any item failed)
   - line 2: `Round: <n>`
   - then one line per item from the checker: `- pass: <item>`, `- fail: <item>: <reason>` or `- ask-first: <item>: <where>`
   - then one line per independent step: `- pass: <step> (independent)` or `- fail: <step> (independent): <reason>`. The step fails when its agent did not run it as written (`could not run: <what did not run>`), or when a finding of the step's top two severities (BLOCKER and MUST-FIX, for example) is `not declared`; name each such finding with its location. Findings of lower severities are listed under its section below and do not fail it.
   - then, if the checker returned notes after its verdict, a blank line, `## Notes`, and the notes as it wrote them
   - then, for each independent step, a blank line, `## <step> (independent)`, and its agent's answer as it wrote it
4. Update the task's board row. Set `updated` to the current date and time (`date '+%Y-%m-%d %H:%M:%S'`), taken now, before step 5 messages the worker.
   - Any `ask-first` line, whatever the round: `round` `n`, `state` `needs-user`, `waiting on` `user`, `next` `decide ask-first item`. Another round cannot fix work the user has not agreed to.
   - All pass: `round` `n`, `state` `validated`, `waiting on` `user`, `next` `merge PR`.
   - Any fail, and `n` < `max check rounds`: `round` `n`, `state` `running`, `waiting on` `worker`, `next` `fix check round <n>`.
   - Any fail, and `n` ≥ `max check rounds`: `round` `n`, `state` `needs-user`, `waiting on` `user`, `next` `decide after <n> failed checks`.
5. Then:
   - `validated`: tell the user in two lines: the task passed, and the PR link from the report if there is one.
   - `running`: send the worker session (its name is the task id) one message: `Check failed. Fix what <absolute path to check.md> lists, and every other instance of the same kind, then report again.` If `command claude agents --json` shows no live session with that name, run `cd <worktree> && command claude --resume <session> --bg "<the same message>"; cd <home>` as one command (not in a `( )` subshell) with the row's `session`. If that fails too, keep `state` `running`, set `waiting on` `user` and `next` `resume <task-id>`, and tell the user.
   - `needs-user`: show the user the `fail` and `ask-first` lines of `check.md` and ask what to do. For an `ask-first` line, ask whether to keep the change.
