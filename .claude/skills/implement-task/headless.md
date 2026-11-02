# Headless mode

How `/implement-task` runs when nobody is there to answer a gate — under
`scripts/issue-to-pr.sh`, which starts one session per phase:

```
/implement-task --headless --phase <1|2|3|4> --base <branch> <issue URL> [--spec specs/<slug>]
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
| 4 Review | the `## Standards` and `## Spec` reports `/code-review` produced, verbatim |

**Blocked** is for the cases where the phase file says to stop and surface
something to the user — a task that contradicts a constraint you found, a slice
that cannot be completed. Say what blocked you and what you tried. An open
question you can answer with a reasonable, stated assumption is not a blocker.

## What changes in each phase

- **Phase 1** reads the issue from the prompt. The spec folder is your choice, as
  in the phase file — extend an existing one where it fits. The harness finds it
  afterwards from the `gates/1-research.md` you add, so add exactly one. Fill
  `## Acceptance Criteria` in `design.md` with one item per requirement in the
  issue, each tagged with the test that will prove it, in the format the
  template gives. The test may not exist yet — Phase 3 writes it — but its full
  name must match exactly then: the harness looks it up by that name in its own
  run, and only a `passed` result counts.
- **Phase 2** reads `<spec>/design.md` from the `--spec` it is given. The base is
  `--base`; do not ask for it. The harness has already created and checked out
  the working branch, so skip the "branch from the base" step — but still commit
  the spec, and record the base under `## Session Notes`. Fill the fenced block
  under `## Verification` with one `yarn test <path>` line per test file your
  slices' "Verified by" names. The harness runs exactly these, after Phase 3,
  and nothing else is accepted: no other command, no flags, no globs, no shell
  syntax. A path that does not exist by the end of Phase 3 counts as a failure.
  Declare every test file an acceptance criterion names: an undeclared file is
  not run, and its criteria count as uncovered.
- **Phase 3** reads `<spec>/implementation.md`. Commit each slice as the phase
  file says, and set `## Status: complete` (or `blocked`) as usual. Then, instead
  of pushing and opening the PR:
  - write the PR body, from the template in `phases/3-implement.md`, to
    `.claude/headless-runs/pr-body.md` at the repository root. That path is
    gitignored; do not commit it.
  - do not run `git push` or `gh pr create`. The harness pushes, re-runs the
    checks itself, and opens the PR with your body followed by its evidence.

- **Phase 4 — Review** has no phase file: run the `/code-review` skill on the
  branch, with everything it would otherwise ask for given up front, so it never
  stops to ask:
  - the fixed point is `origin/<base>`;
  - the spec is `<spec>/design.md` together with the issue URL (read it with
    `gh issue view`) — there is no `docs/agents/issue-tracker.md` to consult;
  - the standards source is `CONTRIBUTING.md`, plus the skill's smell baseline.

  Change no code. Besides the gate file, write the findings to
  `.claude/headless-runs/review.json` at the repository root (gitignored; do not
  commit it), one entry per finding, keeping the skill's own categories:

  ```json
  { "findings": [
    { "axis": "spec", "kind": "missing", "severity": "hard",
      "summary": "…", "where": "path:line", "quote": "the spec line" }
  ] }
  ```

  `axis` is `spec` or `standards`. `kind` is `missing`, `creep` or `wrong` for
  spec, `violation` or `smell` for standards. `severity` is `hard` or
  `judgement` — smells are always `judgement`. An empty `findings` array is a
  valid review; a missing file is not.

Report check results honestly in the PR body as always: the harness's evidence
sits beside it, and a body that disagrees with it is the first thing a reviewer
will see.
