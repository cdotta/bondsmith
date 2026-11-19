---
name: setup
description: First-time setup of Bondsmith in the repo the orchestrator will run from (the home repo). Creates orchestrator/config.md, orchestrator/board.md, orchestrator/tasks/, the pointer block in CLAUDE.md, and the scripts orchestrator/start and orchestrator/watch. Safe to run again; it only adds what is missing and rewrites the two scripts.
allowed-tools: Read(/${CLAUDE_PLUGIN_ROOT}/templates/**)
---

# Bondsmith setup

Run in the current directory, which is the home repo. Ask the user nothing. Never overwrite or edit an existing file, except to append the pointer block in step 4 and the ignore line in step 5, and to rewrite `orchestrator/start` and `orchestrator/watch` in step 6. Use the Read and Write tools; templates are in `${CLAUDE_PLUGIN_ROOT}/templates/`.

1. If `orchestrator/tasks/.gitkeep` does not exist, write it as an empty file.
2. If `orchestrator/config.md` does not exist:
   1. Read `${CLAUDE_PLUGIN_ROOT}/templates/config.md`.
   2. Read `CLAUDE.md` if it exists. If it lists repos with their paths, keep the `home` row and add one Repos row per listed repo: `name` and `path` as listed, `owns` from the repo's description or empty, `base` the output of `git -C <path> symbolic-ref --short refs/remotes/origin/HEAD` (for example `origin/main`), or `HEAD` if that command fails, `worktree dir` `.claude/worktrees`, `review steps` `none`.
   3. Write the result to `orchestrator/config.md`.
3. If `orchestrator/board.md` does not exist, copy `${CLAUDE_PLUGIN_ROOT}/templates/board.md` to it unchanged.
4. If `CLAUDE.md` has no line that is exactly `## Orchestrator`, append this block to it (create the file if missing), with one blank line before it:

   ```markdown
   ## Orchestrator
   Task state lives in `orchestrator/board.md`; settings in `orchestrator/config.md`.
   To manage tasks, run `/bondsmith:orchestrate`. Do not edit `board.md` in any other session.
   ```

5. For each Repos row whose `path` is `.`, if `.gitignore` has no line `<worktree dir>/`, append that line to it (create the file if missing).
6. Read `${CLAUDE_PLUGIN_ROOT}/templates/start` and write it to `orchestrator/start`, changing only `<plugin root>`: replace it with `${CLAUDE_PLUGIN_ROOT}`, or with nothing (leaving `plugin_dir=''`) if that path is inside `~/.claude/plugins/`, where installed plugins live. The script reads `config.md` each time it runs. Then read `${CLAUDE_PLUGIN_ROOT}/templates/watch` and write it to `orchestrator/watch` unchanged.
7. Tell the user, in a short list:
   - which files you created and which already existed;
   - which Repos rows you filled from `CLAUDE.md`, if any, and that `owns`, `base` and `review steps` need checking;
   - to edit `orchestrator/config.md`: Repos, Workers, Catalogue;
   - that `claude` must have been started once, interactively, in each target repo and in this repo, or workers cannot start there;
   - to launch the orchestrator with `sh orchestrator/start`, or `sh orchestrator/start "<a new task>"`; edits to `config.md` apply at the next start, and the script warns about any repo that is missing or not yet trusted;
   - that the script starts `claude` directly, so a shell function or alias named `claude` does not apply; settings it adds belong in `extra settings`.
