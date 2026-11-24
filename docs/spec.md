# Bondsmith: design spec

Written 2026-11-18. Status: v0.1 built and in early use; the acceptance trial in section 12 is not complete.

Bondsmith is a Claude Code plugin. One long-lived **orchestrator** session on a strong model takes tasks from the user, hands each to a **worker** session on a cheaper model in the right repository, checks the result, and records completion. The user talks only to the orchestrator.

## 1. Goals and what is left out

Goals:

1. The orchestrator runs from a "home" repo and manages tasks in several sibling repos. Each worker runs inside its target repo, so that repo's `CLAUDE.md` applies.
2. The orchestrator's context stays small, and a new orchestrator session can replace the old one at any time (daily in practice) without losing a task.
3. The orchestrator picks which home-repo material each worker needs, sends it, and later validates the output against the same material.
4. Only the orchestrator marks a task complete.
5. Nothing in the plugin names a specific repo, ticket system, person or review tool. All of that is read from files in the user's home repo.

Left out, on purpose:

- No daemon, server, database or UI. Skills, one agent definition and Markdown templates only.
- No merging, deploying or closing tickets. The user merges.
- No workers on other machines, and no two orchestrators on one board.
- No ticket-system integration. A catalogue row can tell a worker what to do with a ticket.

## 2. Roles

| Role | What it is | Model | Writes |
|---|---|---|---|
| User | The person | — | `config.md`; answers questions; merges PRs |
| Orchestrator | An interactive session started in the home repo | `fable` (user's choice at launch) | `board.md`, each task's `brief.md` |
| Worker | A background session started in a worktree of the target repo, one per task | From `config.md`, default `opus` | Its own `report.md`; code in its worktree |
| Checker | A subagent of the orchestrator, one per check round, with no Edit or Write tools | From `config.md`, default `opus` | Returns a result; the orchestrator saves it as `check.md` |

## 3. Files in the home repo

Created by the setup skill (section 9). All Markdown, because every reader is a model: no parser.

```
<home>/
├── CLAUDE.md                     # setup appends the pointer block below
└── orchestrator/
    ├── config.md                 # user-edited: repos, workers, catalogue
    ├── board.md                  # orchestrator-only: one line per task
    ├── start                     # setup writes: launches the orchestrator
    ├── watch                     # setup writes: wakes it when a worker is blocked
    └── tasks/<task-id>/
        ├── brief.md              # orchestrator writes at spawn
        ├── report.md             # worker overwrites on every state change
        └── check.md              # latest check round result
```

`<task-id>` is the ticket id when there is one, otherwise a short slug. It is also the worker's session name and its worktree name.

Pointer block appended to `CLAUDE.md` (it is re-loaded after compaction and by every new session, which is how a new orchestrator finds the board):

```markdown
## Orchestrator
Task state lives in `orchestrator/board.md`; settings in `orchestrator/config.md`.
To manage tasks, run `/bondsmith:orchestrate`. Do not edit `board.md` in any other session.
```

### 3.1 `config.md`

First line `format: 1`. Three tables.

**Repos**

| Column | Meaning |
|---|---|
| name | Short name used on the board |
| path | Path from the home repo, e.g. `../api`; `.` is the home repo itself. The template's only row is `home` with path `.`, so a first task needs no config editing |
| owns | One phrase, used to route a task to a repo |
| base | Ref a worktree is cut from, e.g. `origin/main` |
| worktree dir | Where worktrees go inside the clone, e.g. `.claude/worktrees` |
| review steps | Skills or commands that must run on the final diff before a PR, comma-separated. A step marked ` (worker)` is one the checker cannot run, such as a review that starts its own subagents (a subagent cannot start one); the checker accepts the worker's run if the report names the final commit as where it last ran. A step marked ` (independent)` the checker skips; each check round runs it in a `general-purpose` agent beside the checker instead (section 7) |

**Workers** (one row of settings)

| Column | Meaning |
|---|---|
| worker model | e.g. `opus` |
| checker model | e.g. `opus` |
| permission mode | e.g. `acceptEdits` |
| allowed tools | Value for `--allowedTools`, e.g. `Bash(git *) Bash(gh *) Bash(npm test *)` |
| extra settings | Optional settings file passed with `--settings`, for plugins the worker needs |
| max check rounds | Default `2` |
| orchestrator name | The session name every orchestrator is launched with, e.g. `bondsmith`. Workers message this name |
| orchestrator model | Model the start script launches the orchestrator on, default `fable` |

**Catalogue**

| Column | Meaning |
|---|---|
| file | Path in the home repo. The catalogue points at files; it never copies them |
| send when | Plain-language condition, e.g. "task opens a PR in any repo", "task writes a spec" |
| validate | `yes` if the checker must check the output against this file |

### 3.2 `board.md`

First line `format: 1`. One table row per task:

| Column | Meaning |
|---|---|
| task | `<task-id>` |
| repo | Name from the Repos table |
| worktree | Absolute path |
| session | The worker's full `sessionId` from `claude agents --json`; `claude --bg` prints only a short one |
| state | See section 4 |
| round | Check rounds run, the same number as `check.md`'s `Round:` line. Reset to `0` when the user asks for changes after `validated` |
| waiting on | `worker`, `checker`, `user`, or empty |
| next | One phrase |
| updated | Date and time of the last change to this row |
| notes | A few words on an ordering or dependency with another task, e.g. `merge right after login-fix`; usually empty |

Closed and dropped rows move to a `## Finished` table at the bottom, so the top table is only live work.

### 3.3 `brief.md`

```markdown
# <task-id>: <one-line goal>

## Goal
<one sentence>

## Done when
- [ ] <check the checker can verify, with the command or evidence that proves it>

## Read first
- <absolute path>: <why>            # catalogue rows whose "send when" matched

## Checked against
- <absolute path>                   # the subset with validate = yes
- Review steps: <from the Repos row>

## Facts and decisions
Base: <base from the Repos row>
<what the worker must not re-decide>

## Ask first
<what needs the user's yes>

## Worker rules
<the block in section 6, copied as is>
```

The worker rules travel inside the brief, so a worker needs no plugin installed.

## 4. Task states

Only the orchestrator changes `state`. A worker asks for a change through its report.

| State | Meaning | Entered when | Leaves to |
|---|---|---|---|
| `briefed` | Brief written, worker not started | Orchestrator writes `brief.md` | `running` |
| `running` | Worker is working | Spawn succeeds; or failed items were sent back | `ready-for-check`, `needs-user`, `dropped` |
| `needs-user` | A decision only the user can make | Worker report asks; or max check rounds reached | `running`, `dropped` |
| `ready-for-check` | Worker says it is finished | Worker report says so | `validated`, `running` |
| `validated` | **The completion mark.** Every check passed | Checker returns all pass | `closed`, `running` (user asks for changes) |
| `closed` | Output accepted | PR is merged, or the user says so for non-PR work | — |
| `dropped` | Abandoned | User says so | — |

## 5. Spawning a worker

The orchestrator does this itself, through Bash, for each new task:

1. Pick the repo from the Repos table. Pick catalogue rows whose "send when" fits the task. Write `brief.md`. Add the board row as `briefed`.
2. Cut the worktree with plain git, so the base is known. Fetch only when `base` has the form `<remote>/<branch>`; a base without a remote, such as `main` or `HEAD`, is used as is:

   ```sh
   git -C <repo path> fetch <remote>        # only for a <remote>/<branch> base
   git -C <repo path> worktree add <worktree dir>/<task-id> -b <branch> <base>
   ```

3. Start the worker in it, as one command:

   ```sh
   cd <worktree> && command claude --bg \
     --model <worker model> --name <task-id> \
     --permission-mode <permission mode> --allowedTools <allowed tools> \
     --add-dir <home absolute path> \
     [--settings <extra settings>] -- \
     "Read <home>/orchestrator/tasks/<task-id>/brief.md and do what it says. Your report.md is <home>/orchestrator/tasks/<task-id>/report.md."; cd <home>
   ```

4. Record the session's full id from `claude agents --json` on the board and set `running`.

Three things the probes in section 11 showed, which the skill must respect:

- **Trust.** `claude --bg` refuses to start in a folder the user has never trusted, and refuses an untrusted `--add-dir`. A worktree inside a trusted clone is trusted. So the user must have started `claude` once in each target repo and in the home repo. The start script warns about each untrusted repo at every start, from `projects.<path>.hasTrustDialogAccepted` in `~/.claude.json` (Claude Code's internal state, so the check is skipped without `jq` or that file). When a parent folder is trusted, interactive `claude` shows no prompt in a repo under it and records nothing, while `--bg` still refuses that repo; the script says so and names the parent. A session cannot check trust itself: Claude Code blocks `jq` on `~/.claude.json` from inside a session, since it is outside the working directories. The skill also stops when it sees "Workspace not trusted", and names the repo to trust, not the worktree.
- **One `--settings` only.** When the flag is given twice, the last one replaces the first; they do not merge. If the user's shell wraps `claude` to add `--settings`, call `command claude` so exactly one is passed.
- **No subshell; the repos are working directories.** A `( cd <dir> && ... )` subshell always needs the user's approval, whatever the allow rules say, and so does `env -C`. A plain `cd <dir> && ...` runs unprompted, but only when `<dir>` is inside the session's working directories. So the orchestrator is launched with one `--add-dir` per repo, and every start or resume is `cd <worktree> && command claude ...; cd <home>`, which also moves the orchestrator's own working directory back.
- **`--` before the prompt.** `--allowedTools` takes several values and otherwise swallows the prompt.

`--add-dir` gives the worker read access to the brief and catalogue files and write access to its `report.md`. It also lets the worker edit other home files; the worker rules forbid that, and nothing enforces it.

## 6. Worker rules and the report

Copied into every brief:

```markdown
- Work only in this worktree. In the home repo, write only your own report.md.
- Read every file under "Read first" before you start.
- Before you say you are finished: every "Done when" box is met and you have
  the evidence, and every review step under "Checked against" has run on the
  final diff with its findings fixed in their own commits.
- On every state change, overwrite report.md first, then send one line to the
  session named "<orchestrator name>": "<task-id> report updated". The file is
  the record; the message is only a nudge, and it may fail when no orchestrator
  is running. Do not retry it.
- You never mark the task complete. You report "ready-for-check" and wait.
- Never merge a PR, and never push to the base branch. The user merges.
- With a PR, report "ready-for-check" only once its CI has finished on your
  last commit; the checker takes CI as the test evidence.
- When a check fails you get the path to check.md. Fix what it lists, and every
  other instance of the same kind you find; name those in report.md under Did.
  Fix nothing else.
- Stop only for what is under "Ask first" or a decision only the user can make.
  Then report "needs-user" with the decision, the options and your pick.
```

`report.md`, always the whole current picture, never a log:

```markdown
Task: <task-id>
State: working | ready-for-check | needs-user
Did: <two or three lines>
Evidence: <PR link, commits, test command with its result line>
Reviews: <step>: <n> findings, fixed in <commits>; last run on <commit>      # one line per review step
Done when: <each check>: met | not met, <evidence>
Question: <only for needs-user: decision, options, pick>
Next: <one line>
```

The orchestrator messages a worker by its session name, which is the `<task-id>`. Workers message the fixed orchestrator name, so a new orchestrator needs no hand-over.

## 7. Validation and the completion mark

When a report says `ready-for-check` but itself lists a `not met` item or work it left undone, the orchestrator sends it back without a check and without counting a round. Otherwise it spawns the `checker` subagent with three paths: `brief.md`, `report.md`, and the worktree. It gives the checker nothing else, in particular not its own opinion of the work. The checker:

1. Verifies each "Done when" item itself: runs the named command in the worktree or reads the named evidence. A report line saying "met" is not evidence. With a PR that has CI checks, a test suite's evidence is CI on the worktree's `HEAD` (`gh pr view --json headRefOid,statusCheckRollup`, already allowed); the checker runs the suite locally only without a PR, since a worktree often has no environment of its own.
   When it finds a failure, it searches the whole diff for every other instance of the same kind and lists them all, so a later round does not find what this one could have.
2. Runs every review step from the brief again on the final diff (`git -C <worktree> diff <base>...HEAD`, or the PR). The base is the brief's `Base:` line; without one, every review step fails as could not run. It skips a step marked `(independent)`: for each such step the check round spawns, in parallel with the checker, one `general-purpose` agent, which has the Agent tool, runs the step on the PR (or in a detached worktree of its own), posts and changes nothing, and returns its findings by severity and which the PR body declares. The step fails when it did not run as written or when a finding of the step's top two severities is undeclared.
3. Checks the output against each "Checked against" file.
4. Checks the diff against "Ask first". Work the brief says needs the user's yes, done without a yes recorded under "Facts and decisions", is an `ask-first` line.
5. Returns one line per item, `pass` or `fail` with the reason and location, then a single overall verdict. Ten lines at most beyond the item list.

The orchestrator saves the result as `check.md`: the verdict, the round, the item lines, a line per independent step, then the checker's notes under `## Notes`, then a section per independent step with its agent's findings. Then:

- **All pass:** set `validated`, tell the user in two lines with the PR link.
Every check round sets `round` to its own number.

- **Any fail:** set `running`, send the worker the path to `check.md`. If the worker session has stopped, `claude --resume <session> --bg "<same message>"`.
- **Any `ask-first` line:** set `needs-user` at once, whatever the round, and ask the user whether to keep that change.
- **`round` reaches max check rounds:** set `needs-user` and show the user the failing items.

When the user asks for changes to a `validated` task, or says to go on after max check rounds, the orchestrator stops the old worker session and starts a fresh one in the same worktree with the same name and the current Workers settings, and writes its session id on the board. A session that carried the build, every round and later changes can fill its context window, and the orchestrator cannot see a worker's context use, so the rule is by event. The fresh worker reads `brief.md`, `report.md`, `check.md` and the worktree, which is why the report must name the branch, the head commit, what is uncommitted and what was rejected. An answer to an ordinary `needs-user` question still goes to the same session.

`validated` → `closed` when `gh pr view <pr> --json state` shows merged, checked every turn, or when the user says so. At `closed` the orchestrator asks before stopping the session and removing the worktree, in one question for all tasks closed that turn.

## 8. Keeping the orchestrator small, and the daily restart

Rules in the `orchestrate` skill:

- At the start of every turn, compare each live task's `report.md` modification time with the board row's `updated`, and process any newer report. This catches nudges that were lost.
- Update the board before replying to the user.
- Never read a worker's transcript, a diff, or source code. Investigation goes to a subagent that returns a summary; validation goes to the checker.
- Never hold task detail in the conversation that is not also in `brief.md`, `report.md` or `board.md`.

Starting a new orchestrator (any time; nothing is handed over from the old one):

1. Read `config.md` and `board.md`.
2. `claude agents --json`: match live sessions to board rows by name.
3. For a row whose session is gone and whose state is `running`: `cd <worktree> && command claude --resume <session id> --bg "<what to do next>"; cd <home>`.
4. Run the every-turn rules: process reports newer than their rows, flag blocked workers, check `validated` rows for merged PRs.
5. Tell the user what changed since the board was last written, in one short list.

Launch: `sh orchestrator/start [new task text]`. The setup skill copies `templates/start` there, filling in only the plugin path. The script reads the Repos and Workers tables of `config.md` at every start (columns found by header name), skips and warns about a Repos path that does not exist, warns about an untrusted repo, waits for Enter after any warning when run from a terminal (`claude` takes over the screen and would hide it), and runs:

```sh
exec claude --model <orchestrator model> --name <orchestrator name> --autocompact 200000 \
  --permission-mode acceptEdits [--plugin-dir <plugin root>] [--settings <extra settings>] \
  --add-dir <repo> ...                      # one per Repos row other than `.`
  --allowedTools <rules> -- "/bondsmith:orchestrate $*"
```

- `--autocompact` is its own flag, so compaction at 200k works alongside any `--settings`.
- The allow rules cover the orchestrator's own commands: `command claude --bg *`, `--resume *`, `agents *`, `stop *`, `logs *`; `gh pr view *`; `sh <home>/orchestrator/watch`; `Skill(bondsmith:check)`, since a skill with `allowed-tools` needs approval when the model, not the user, invokes it; and per repo `git -C <repo> remote`, `fetch *`, `worktree *`, with the repo's exact absolute path. A rule like `git -C * fetch *` would also match inserted options such as `-c`, which run arbitrary commands. The checker's commands are not covered and prompt.
- `--permission-mode acceptEdits` lets the orchestrator write the board and briefs without asking; it could also edit repo files, which the skill forbids and nothing enforces.
- The script calls `claude` directly, so a user's shell function or alias does not apply; what it would add belongs in `extra settings`, which the orchestrator gets as well as the workers.
- Writing the repos into `permissions.additionalDirectories` instead was rejected: `.claude/settings.json` is a protected file, so it cannot be written or tested from a `claude -p` session.

## 9. The plugin

```
bondsmith/
├── .claude-plugin/{plugin,marketplace}.json   # the repo is its own marketplace
├── skills/
│   ├── setup/SKILL.md          # creates section 3's files from templates/
│   ├── orchestrate/SKILL.md    # sections 5, 7 and 8
│   ├── check/SKILL.md          # runs one check round by hand: /bondsmith:check <task-id>
│   └── status/SKILL.md         # read-only: board, live session states, report ages
├── agents/checker.md           # section 7; no Edit or Write tools
├── templates/{config,board,brief}.md, templates/start, templates/watch
├── tests/                      # shell tests; all but static.sh drive real sessions
├── docs/spec.md
├── README.md
└── LICENSE                     # MIT
```

Setup rules:

- Never overwrite. If `orchestrator/` exists, add only what is missing.
- Ask nothing. If the home `CLAUDE.md` lists repos with their paths, fill the Repos table from it and say which rows were filled; the user edits `config.md` afterwards anyway. A filled row's `base` is the clone's `origin/HEAD` (for example `origin/main`), or `HEAD` when it has none.
- Append the pointer block once; skip if present.
- For a Repos row with path `.`, add its `worktree dir` to the home `.gitignore`.
- Write `orchestrator/start` (section 8) and `orchestrator/watch` (section 10) on every run; they are the only files setup overwrites. Config edits need no setup run: the script reads `config.md` when it starts.
- `format: 1` at the top of `config.md` and `board.md`. A skill that needs a newer format says what to change and stops.

Users install it from the repo's own marketplace (`/plugin install bondsmith --marketplace cdotta/bondsmith`); a clone loads with `claude --plugin-dir <clone>`. An installed plugin's `${CLAUDE_PLUGIN_ROOT}` is a versioned cache directory, so setup leaves the start script's plugin path empty for it.

## 10. Failure cases

| Case | What happens |
|---|---|
| Worker session stopped (idle timeout, machine restart) | Found at the turn-start or daily check; resumed with `--resume <session> --bg` |
| Worker blocked on a permission prompt | `claude agents --json` shows its state `blocked` with `waitingFor` set; a session that only ended its turn is also `blocked`, with no `waitingFor`, and gets a nudge to write its report. Only rows `waiting on: worker` count. `orchestrator/watch`, run in the background by the orchestrator, polls it every 30 seconds and exits when a worker the board shows `waiting on: worker` is blocked, which wakes the orchestrator without waiting for the user's next turn; every turn also checks. The row gets `waiting on: user`, `next: claude attach <task-id>`, and the user is told. For a permission prompt, a `haiku` subagent runs `command claude logs <task-id>` with Bash (its prompt gives the command in a code block and says to invoke no skill) and names the tool, the command and the rule a "don't ask again" answer would add, so the user can put it in `allowed tools` |
| Worker's nudge never arrives | `report.md` is newer than the board row; picked up at the next turn start |
| Worker reports while no orchestrator runs | Same: the report file waits |
| Check fails | Section 7; back to the same worker, to the user after max rounds |
| Checker cannot run a review step | That item is `fail: could not run`, never a silent pass |
| Two orchestrators on one board | Not supported. Every orchestrator has the same session name, so at start the skill checks `claude agents --json` for another live session with that name; if there is one, it tells the user and does not write the board until they say to continue |
| Worker edits home files it should not | Not prevented. Shows up in the home repo's `git status` |

## 11. Requirements and probe results

Requires Claude Code with background sessions (research preview) and cross-session messaging (v2.1.224 or later).

The design's open questions were probed on 2026-11-18 with Claude Code v2.1.327 on macOS: one Opus background worker in a worktree of a trusted repo, driven by a brief file, plus one read-only subagent as the checker. All passed. Re-run them when the Claude Code version changes much; background sessions are a preview.

| # | Question | Result |
|---|---|---|
| P1 | Does `claude --bg --model opus` run on that model? | Yes: the worker reported `claude-opus-5-5` |
| P2 | Does a `--bg` session started in a worktree stay in it? | Yes: same path, same branch, no second worktree; its commit landed on the task branch |
| P3 | Does it load the worktree's `CLAUDE.md` and the plugins from `--settings`? | Yes to both |
| P4 | Can the worker message the orchestrator by name? | Yes: delivered to an interactive session with no settings change |
| P5 | What happens on a message to a name that does not exist? | It fails at once with `No agent named '<name>' is reachable`; nothing is queued |
| P6 | Can a subagent check a worktree that is not its working directory? | Yes: `git -C <worktree>` and `cd <worktree> && <cmd>` in one command both work, and it loaded and ran a review skill. Its `cd` does not carry to the next command |
| P7 | Does `autoCompactWindow` work through `--settings`? | Yes: the context report showed 200k in place of 1M |
| P8 | Does `claude --resume <session id> --bg "<message>"` continue a stopped worker? | Yes, run from the worktree, with its history intact |

Also found:

- The trust and single-`--settings` rules in section 5.
- The checker's read-only limit is an instruction, not a lock. A subagent without Edit and Write still has Bash; the one probed refused to write because its instructions said so. `agents/checker.md` must say it plainly.

Found while building v1, same version:

- A subshell `( cd <dir> && ... )` and `env -C <dir> ...` always need approval; `cd <dir> && ...` runs unprompted only inside the session's working directories (section 5).
- A skill's text gets `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_SESSION_ID}` and `$ARGUMENTS` substituted. The orchestrator uses `${CLAUDE_SESSION_ID}` to tell itself apart from another live session of the same name; a `claude -p` session is listed by `claude agents --json` as `interactive`.
- A `claude -p` session denies reads outside its working directories. A skill grants itself the template reads with `allowed-tools: Read(/${CLAUDE_PLUGIN_ROOT}/templates/**)`; an absolute path in a rule needs the leading `//`.
- Every file under a `--plugin-dir` is write-protected ("sensitive file"), so a home repo must not sit inside the plugin's directory. `tests/e2e.sh` loads a copy of the plugin for this reason.
- `.claude/settings.json` cannot be written from `claude -p`, even with an allow rule.
- A `claude -p` session that spawns the checker waits for its result before it exits, when the skill says to wait.
- `Skill` is accepted in an agent definition's `tools` list.
- `--autocompact 200000` sets the compaction window to 200k, alongside a `--settings` flag in the same command.
- With allow rules for `command claude *`, the `git` calls, and `gh pr view *`, every orchestrator command ran unprompted, including `cd <worktree> && command claude ...; cd <home>`. `date` and `date -r` need no rule. Claude Code warns that a rule like `Bash(git -C * fetch *)` also matches inserted options such as `-c`, which can run arbitrary commands, so generated rules should name each repo path.
- A plugin command given as the first prompt of a non-`-p` session runs, with its arguments.
- Trust belongs to a git repo, not to its parent folder: a nested repo inside a trusted one is untrusted.
- A worker in a worktree of the home repo itself, with `--add-dir <home>`, works.
- A `claude --bg` session does not inherit the environment of the process that starts it.
- A `claude -p` session does not exit while a background Bash task it started still runs, so `tests/e2e.sh` sets `BONDSMITH_WATCH=off`, which makes the watch exit at once.
- A loop such as `until <cmd>; do sleep 30; done` always needs approval, even with an allow rule for each command in it; that is why the watch is a script with one exact rule.
- `claude agents --json` reports `state: blocked` for a background session waiting on a permission prompt (`status: waiting`, `waitingFor: permission prompt`) and also for one that has finished its turn (`status: idle`, no `waitingFor`).
- `claude stop` finds a session only by its short `id` from `claude agents --json`, not by its name or full `sessionId`; `claude logs` takes the name or the short id; `claude --resume` takes the full `sessionId`.
- A background session started in a repo's main checkout moves itself into a new `.claude/worktrees/<name>` worktree before its first edit. Workers are always started in a worktree, so this does not affect them.

Not probed:

- The real review skills and test commands of a product repo run by the checker (one small review skill was run).
- `--resume` from a directory other than the worktree.
- A worker left idle past the timeout, or a machine restart.
- Two workers at once.
- `--allowedTools` beyond `Bash(git *)` and `Bash(pwd)`; the probe worker asked for nothing else.

## 12. Acceptance

Trial, in one home repo, with real tickets (in progress):

1. Setup creates the files and leaves existing ones untouched when run twice.
2. Two tasks in two different repos run at the same time, each on the worker model, each following its own repo's `CLAUDE.md`.
3. A worker that skips a review step is caught by the checker and the task does not reach `validated`.
4. A brief contains the catalogue files that fit the task and none that do not.
5. Closing the orchestrator mid-task and starting a new one the next day loses nothing: the new one reports the correct state from the files alone.
6. After a full day of use, the orchestrator's context is under the compaction threshold or has compacted without losing a task.

Release, after the trial:

7. `rg` over the repo finds no private repo, ticket, person or company name.
8. A second person installs it from the marketplace and reaches a `validated` task using only the README.
