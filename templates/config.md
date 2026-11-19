format: 1

# Bondsmith config

## Repos

The repositories workers run in. `path` is relative to this repo; `.` is this repo itself, so the first task needs no other repo. Add a row per repo, for example `| api | ../api | backend API | origin/main | .claude/worktrees | none |`. `review steps`: skills or commands that must run on the final diff before a PR, comma-separated, or `none`. Mark a step the checker cannot run, such as one that starts its own subagents, with ` (worker)`, for example `pr-review (worker)`: the checker then accepts the worker's run on the final commit instead of running it again.

| name | path | owns | base | worktree dir | review steps |
|---|---|---|---|---|---|
| home | . | this repo | HEAD | .claude/worktrees | none |

## Workers

One row of settings for workers, the checker and the orchestrator. `orchestrator name` is the session name every orchestrator is launched with; workers message this name. `extra settings` is a settings file passed with `--settings` to workers and the orchestrator, for plugins they need, or `(none)`. `allowed tools` is what workers may run without asking: add the test, build and lint commands they need, for example `Bash(npm test *)`, or each one stops the worker on a prompt.

| worker model | checker model | permission mode | allowed tools | extra settings | max check rounds | orchestrator name | orchestrator model |
|---|---|---|---|---|---|---|---|
| opus | opus | acceptEdits | Bash(git *) Bash(gh *) | (none) | 2 | bondsmith | fable |

## Catalogue

Files in this repo a worker may need. The catalogue points at files; it never copies them. `validate` is `yes` if the checker must check the output against the file. Example row: `| docs/pr-rules.md | task opens a PR in any repo | yes |`.

| file | send when | validate |
|---|---|---|
