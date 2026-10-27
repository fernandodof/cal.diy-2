# Issue-to-PR Harness Implementation

## Status: in-progress

## Completed

1. **Green path, issue to draft PR** — proves issue → worktree → agent session →
   collector → judge → push → `gh pr create --draft` works end to end
   - `scripts/issue-to-pr.sh`, `scripts/implement-evidence.sh` (diff, commits, agent
     summary, biome on changed files), `scripts/implement-verdict.sh` (schema check,
     all-green rule, rendered block between the evidence markers),
     `scripts/headless-task.sh` (`--workdir`), `docs/harness/implement-evidence-schema.md`
   - Verified by: `./scripts/issue-to-pr.test.sh` — fake `claude` commits a file in
     the worktree, fake `gh` records calls, real git pushes to a temp bare remote;
     asserts one `gh pr create --draft --base main` whose body holds the block

2. **Red path is honest** — proves every failure the judge knows about reaches the
   PR as red evidence plus `agent:needs-help`, and zero commits opens no PR
   - `scripts/implement-verdict.sh` (null facts, failed check, failed agent,
     zero commits, unknown schema → exit 2), `scripts/issue-to-pr.sh` (label
     creation if missing, label on red, no-PR exit on zero commits)
   - Verified by: `./scripts/implement-verdict.test.sh` (fixtures: green, failing
     check, null fact, failed agent, zero commits, wrong schema) and red / zero-commit
     cases in `./scripts/issue-to-pr.test.sh`

## In Progress

## Blocked

## Next Steps

1. **Agent session is locked down** — proves the agent cannot push or open a PR
   and can run the checks #11 was denied
   - `scripts/headless-task.sh` (`--allowed-tools`, `--disallowed-tools`),
     `scripts/issue-to-pr.sh` (allowlist, denylist, headless prompt rules)
   - Verified by: `./scripts/issue-to-pr.test.sh` asserting the flags fake `claude`
     received; `./scripts/headless-task.sh` with no new flags behaves as before
2. **Worktree builds and type-checks for real** — proves the evidence tests the
   worktree's code, not the main checkout's
   - `scripts/issue-to-pr.sh` (`yarn install --immutable` with
     `YARN_CACHE_FOLDER` on the main checkout's cache),
     `scripts/implement-evidence.sh` (always-on
     `yarn turbo run type-check --filter=@calcom/web`)
   - Verified by: `./scripts/issue-to-pr.test.sh` (fake `yarn` records the install
     and the type-check call), then one real
     `./scripts/implement-evidence.sh` run against a worktree of this branch

## Session Notes

- Base branch: `main` (confirmed at the Phase 2 gate). Working branch
  `feat/issue-to-pr-harness`.
- Review-size check: 5 non-test files, within `specs/README.md`'s 5–7; the
  500-line limit is the risk and is re-checked at the Phase 3 gate.
- Slice 1 done: green path end to end against fakes, 12 orchestrator checks pass.
  Next: slice 2, the red path and the judge fixture tests. `shellcheck` is not
  installed here, so scripts are not linted.
- Slice 2 done: the verdict fails closed on nulls, failed checks, a failed session
  and zero commits (15 fixture checks); red runs open a labelled draft PR, zero
  commits opens none (25 orchestrator checks). Next: slice 3, locking down the
  agent session.
