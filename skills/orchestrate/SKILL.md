---
name: orchestrate
description: Run the Bondsmith orchestrator in the home repo. Starts or resumes from orchestrator/board.md, takes a new task and starts a worker session for it, processes worker reports, runs checks and closes tasks. Usage /bondsmith:orchestrate [new task text].
allowed-tools: Read(/${CLAUDE_PLUGIN_ROOT}/templates/**)
---

# Bondsmith orchestrator

You are the orchestrator. Your working directory is the home repo; `<home>` is its absolute path. Settings are in `orchestrator/config.md`. Only you write `orchestrator/board.md` and the `brief.md` files. Write every `claude` call as `command claude`. Start or resume a session in another folder only as one command, `cd <folder> && command claude ...; cd <home>`, never in a `( )` subshell, which always needs approval. A time is always `date '+%Y-%m-%d %H:%M:%S'`.

Run the start routine. Then, if `$ARGUMENTS` is not empty, run "New task" with `$ARGUMENTS` as the task.

## Start routine

1. If `orchestrator/config.md` does not exist, tell the user to run `/bondsmith:setup` and stop. If line 1 of `orchestrator/config.md` or `orchestrator/board.md` is not `format: 1`, name the file, say this plugin reads format 1, and stop.
2. Read `orchestrator/config.md` and `orchestrator/board.md`. If a board table has no `notes` column, add it as the last column, empty.
3. Each Repos row's `path`, resolved against `<home>`, must be one of this session's working directories, or you cannot start workers there. If one is not, tell the user to relaunch with `sh orchestrator/start`, which adds every Repos path, and stop.
4. Run `command claude agents --json`. If it lists a session whose `name` is the `orchestrator name` and whose `sessionId` is not `${CLAUDE_SESSION_ID}` (this session), another orchestrator is running: tell the user, and do not write the board until they say to continue.
5. Match the listed sessions to Live rows by `name`, which is the task id. For each row in state `running` with no session of that name: `cd <worktree> && command claude --resume <session> --bg "Continue the task in <home>/orchestrator/tasks/<task-id>/brief.md."; cd <home>`.
6. Run "Every turn".
7. Start the watch: run `sh <home>/orchestrator/watch` with Bash in the background (`run_in_background`), exactly so, as the allow rule matches that text. It exits with `<task-id> blocked` when a worker the board shows `waiting on` `worker` stops on a prompt. When it does, run "Every turn" at once, from step 1, then start the watch again the same way. If it exits any other way (for example `jq is missing`, or `off`), tell the user once that blocked workers show up only at your next turn, and do not restart it. Start only one watch per session: not again after a compaction while one runs.
8. Tell the user what changed since the board was last written, as one short list.

## Every turn

1. At the start of every turn, for each Live row, compare `date -r <home>/orchestrator/tasks/<task-id>/report.md '+%Y-%m-%d %H:%M:%S'` with the row's `updated`. If the report is newer, process it by its `State:` line:
   - `ready-for-check`, but a `Done when` line says `not met`, or the report says it left something of the brief or of check.md undone: do not run a check. Take the time, set `waiting on` `worker`, `next` `finish open items`, `updated` that time, and send the worker session (name = task id) `Your report lists open items: <them>. Finish them, then report ready-for-check again.` If it is not live, resume it as in start routine step 5 with that message. `round` stays unchanged.
   - `ready-for-check` otherwise: set `waiting on` `checker`, then follow the `bondsmith:check` skill for that task.
   - `needs-user`: set `state` `needs-user`, `waiting on` `user`, and show the user the report's `Question:` line.
   - `working`: set `next` from the report's `Next:` line, and `updated`.
   - Whatever the state: if the report names an ordering or dependency on another task (merge together, wait for another PR), or the user states one, write it in the row's `notes` in a few words. Clear it when it no longer holds.
2. Run `command claude agents --json`. A session is `blocked` both when it waits on a prompt (`waitingFor` is set) and when it has simply ended its turn (no `waitingFor`), so only rows with `waiting on` `worker` count, after step 1 has processed their reports. For each such row whose session (matched by `name` = task id) has `state` `blocked`: with no `waitingFor`, the worker stopped without reporting. If the row's `next` is not yet `nudged for report`, take the time, set `next` `nudged for report` and `updated`, and send it `Write report.md with your current state, then send the one-line message.` If it already is, set `waiting on` `user`, `next` `claude attach <task-id>`, and `updated`, and tell the user the worker stopped without a report. Then stop there for that row. With `waitingFor` set, the worker waits on a prompt: set `waiting on` `user`, `next` `claude attach <task-id>`, and `updated`, and tell the user to run `claude attach <task-id>` to answer it. If the session's `waitingFor` is `permission prompt`, first spawn a subagent on model `haiku` with this prompt and nothing else: `Run command claude logs <task-id> once. It prints a terminal screen with escape codes; near its end is a permission prompt. Reply in at most three lines: the tool, the exact command or path it asks for, and the rule its "don't ask again" option names, if any. Run nothing else.` Pass its answer on to the user, and if it names a rule, say that adding it to `allowed tools` in `orchestrator/config.md` stops later workers asking. When a row with that `next` is no longer blocked, set `waiting on` `worker` and `next` `wait for report`.
3. For each `validated` row whose report has a PR link, run `gh pr view <link> --json state`. If the state is `MERGED`, close the task (see "Closing").
4. A message "<task-id> report updated" from a worker means: run step 1 now.
5. Update the board before you reply to the user. Set `updated` on every row you change. When the change goes with starting, resuming or messaging a worker, take the time before you start, resume or message it, so a report it writes afterwards is newer.
6. Never read a worker's transcript, a diff or source code. To investigate, spawn a subagent that returns a short summary. To validate, use the `bondsmith:check` skill.
7. Never hold task detail in the conversation that is not also in `brief.md`, `report.md` or `board.md`.
8. Set the new state before you message or resume a worker. If the message fails and the resume fails too, keep that state, set `waiting on` `user` and `next` `resume <task-id>`, and tell the user what failed.

## New task

1. Task id: the ticket id if the task has one, otherwise a lowercase slug of at most 30 characters. It must match `[A-Za-z0-9._-]+` and must not already be on the board.
2. Repo: the Repos row the task names, otherwise the one whose `owns` fits. If none fits or two do, ask the user. Its path, resolved against `<home>` to an absolute path with no `.` or `..` parts (`<home>` itself for `.`), is `<repo>`; write it exactly so in every `git -C <repo>` command, because the start script's allow rules match that text. The worktree is `<repo>/<worktree dir>/<task-id>`, as an absolute path.
3. Catalogue: pick every row whose `send when` fits the task.
4. Read `${CLAUDE_PLUGIN_ROOT}/templates/brief.md` and write `orchestrator/tasks/<task-id>/brief.md` from it:
   - Fill every section. Each "Done when" item names the command or evidence that proves it.
   - Read first: `<home>/<file>: <why>` for each picked catalogue row; leave the section empty if none.
   - Checked against: `<home>/<file>` for each picked row with `validate` = `yes`, then `- Review steps: <the repo's review steps>`, copied unchanged, markers such as ` (worker)` and ` (independent)` included.
   - Facts and decisions: start with the line `Base: <base>`, the repo's `base`.
   - In Worker rules, replace `<orchestrator name>` with the configured name and `<task-id>` with the task id.
   - Remove the `<!-- -->` comment lines.
5. Add a Live row: the task id, repo name, worktree, empty session, `briefed`, `0`, `orchestrator`, `start worker`, the time, empty notes.
6. Cut the worktree. If `base` has the form `<remote>/<branch>` and `<remote>` is listed by `git -C <repo> remote`, first run `git -C <repo> fetch <remote>`. A base without a remote is used as is. Then run `git -C <repo> worktree add <worktree> -b <task-id> <base>`.
7. Take the time; it becomes the row's `updated` in step 9. Then start the worker. Pass each allowed tool as its own quoted argument; add `--settings <extra settings>` only when `extra settings` is not `(none)`; keep the `--` before the prompt:

   ```sh
   cd <worktree> && command claude --bg --model <worker model> --name <task-id> \
     --permission-mode <permission mode> --allowedTools "<tool>" "<tool>" \
     --add-dir <home> -- \
     "Read <home>/orchestrator/tasks/<task-id>/brief.md and do what it says. Your report.md is <home>/orchestrator/tasks/<task-id>/report.md."; cd <home>
   ```

8. If the output says "Workspace not trusted" or "Added folder not trusted": leave the row `briefed`, set `waiting on` `user` and `next` `trust <folder>`, and stop. The folder to trust is the repo, `<repo>`, for "Workspace not trusted", and `<home>` for "Added folder not trusted"; never the worktree, since trusting the repo covers all its worktrees. Tell the user to run `claude` once in that folder, accept the trust prompt, exit, and ask you to continue. Add that if no prompt appears, a parent folder is already trusted, which hides the prompt and records nothing for the repo; `sh orchestrator/start` names that parent.
9. Otherwise run `command claude agents --json` and set the row's `session` to the `sessionId` of the entry whose `name` is the task id (the start command prints only a short id); if there is none yet, use the printed id. Set `state` `running`, `waiting on` `worker`, `next` `wait for report`, `updated` the time from step 7, and tell the user in two lines: the task id and repo, and that the worker is running.

## Answer from the user

When the user answers a `needs-user` task's question, or says to go on after the check round limit: write the answer into the brief under "Facts and decisions", take the time, set `state` `running`, `waiting on` `worker`, `next` `continue after answer`, `updated` that time, then send the worker session (name = task id) the message `The brief changed: <brief path>. Continue.` If it is not live, resume it as in start routine step 5 with that message. Leave `round` unchanged.

## Changes after validation

If the user asks for changes to a `validated` task: append them to the brief under "Done when", set `round` `0`, `state` `running`, `waiting on` `worker`, and send the worker session (name = task id) the message `The brief changed: <brief path>. Do the new items, then report again.` If it is not live, resume it as in start routine step 5 with that message.

## Closing

1. A `validated` task is `closed` when `gh pr view` shows it merged, or when the user says so for work without a PR. A task is `dropped` only when the user says so.
2. Set the state, then move the row from `## Live` to `## Finished`.
3. Ask the user once, for all tasks closed or dropped this turn, whether to stop their sessions (`command claude stop <id>`, with the short `id` that `command claude agents --json` lists for the task's name; `stop` takes neither the name nor the full session id) and remove their worktrees (`git -C <repo> worktree remove <worktree>`). List them by task id. Do neither without a yes.

## Failure cases

- A worker session has stopped: start routine step 5 resumes it.
- A worker's message never arrived, or it reported while no orchestrator ran: "Every turn" step 1 finds the newer report.
- A check fails, or a review step could not run: the `bondsmith:check` skill handles it.
- Another orchestrator is live: start routine step 4.
- `git status` in the home repo shows changes you did not make outside `orchestrator/tasks/<task-id>/report.md`: tell the user which worker's task they belong to, if you can tell, and change nothing.
