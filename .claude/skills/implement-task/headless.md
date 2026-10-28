# Headless mode

How `/implement-task` runs when nobody is there to answer a gate — under
`scripts/issue-to-pr.sh`, which starts one session per phase:

```
/implement-task --headless --phase <1|2|3> --base <branch> <issue URL> [--spec specs/<slug>]
```

Run the named phase exactly as its phase file says, with the changes below, and
nothing else. Do not start the next phase: the harness does, in a new session
that reads only your handoff file.

## The gate writes instead of waiting

Where the phase file says **Gate**, write `specs/<slug>/gates/<n>-<phase>.md`
(`1-research.md`, `2-plan.md`, `3-implement.md`), commit it with the phase's
other files, and stop. The file's **first line** is the outcome:

```
Outcome: continue
```

or `Outcome: blocked`. Below it, what the gate would have shown the user:

| Phase | The gate file holds |
|---|---|
| 1 Research | the design's Overview, the file list, and every open question **with the assumption you made in place of an answer** |
| 2 Plan | the numbered slices and the base branch |
| 3 Implement | `git diff <base> --stat` |

**Blocked** is for the cases where the phase file says to stop and surface
something to the user — a task that contradicts a constraint you found, a slice
that cannot be completed. Say what blocked you and what you tried. An open
question you can answer with a reasonable, stated assumption is not a blocker.

## What changes in each phase

- **Phase 1** reads the issue from the prompt. The spec folder is your choice, as
  in the phase file — extend an existing one where it fits. The harness finds it
  afterwards from the `gates/1-research.md` you add, so add exactly one.
- **Phase 2** reads `<spec>/design.md` from the `--spec` it is given. The base is
  `--base`; do not ask for it. The harness has already created and checked out
  the working branch, so skip the "branch from the base" step — but still commit
  the spec, and record the base under `## Session Notes`.
- **Phase 3** reads `<spec>/implementation.md`. Commit each slice as the phase
  file says, and set `## Status: complete` (or `blocked`) as usual. Then, instead
  of pushing and opening the PR:
  - write the PR body, from the template in `phases/3-implement.md`, to
    `.claude/headless-runs/pr-body.md` at the repository root. That path is
    gitignored; do not commit it.
  - do not run `git push` or `gh pr create`. The harness pushes, re-runs the
    checks itself, and opens the PR with your body followed by its evidence.

Report check results honestly in the PR body as always: the harness's evidence
sits beside it, and a body that disagrees with it is the first thing a reviewer
will see.
