# <task-id>: <one-line goal>

## Goal
<one sentence>

## Done when
- [ ] <check the checker can verify, with the command or evidence that proves it>

## Read first
<!-- catalogue rows whose "send when" matched -->
- <absolute path>: <why>

## Checked against
<!-- the Read first files with validate = yes -->
- <absolute path>
- Review steps: <from the Repos row>

## Facts and decisions
Base: <base from the Repos row>
<what the worker must not re-decide>

## Ask first
<what needs the user's yes>

## Worker rules
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
- report.md must let a successor continue without this session, which a later
  round may hand to a fresh worker: the branch, the head commit, what is
  uncommitted in the worktree, and what was tried and rejected.

report.md, always the whole current picture, never a log:

```markdown
Task: <task-id>
State: working | ready-for-check | needs-user
Did: <two or three lines>
Branch: <branch> at <head commit>; uncommitted: <paths, or none>
Rejected: <what was tried and rejected, and why, or none>
Evidence: <PR link, commits, test command with its result line>
Reviews: <step>: <n> findings, fixed in <commits>; last run on <commit>      # one line per review step
Done when: <each check>: met | not met, <evidence>
Question: <only for needs-user: decision, options, pick>
Next: <one line>
```
