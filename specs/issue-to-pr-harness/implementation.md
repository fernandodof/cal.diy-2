# Issue-to-PR Harness Implementation

## Status: complete

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

3. **Agent session is locked down** — proves the agent cannot push or open a PR
   and can run the checks #11 was denied
   - `scripts/headless-task.sh` (`--allowed-tools`, `--disallowed-tools`),
     `scripts/issue-to-pr.sh` (allowlist, denylist, headless prompt rules)
   - Verified by: `./scripts/issue-to-pr.test.sh` asserting the flags fake `claude`
     received; `./scripts/headless-task.sh` with no new flags behaves as before

4. **Worktree builds and type-checks for real** — proves the evidence tests the
   worktree's code, not the main checkout's
   - `scripts/issue-to-pr.sh` (`yarn install --immutable` with
     `YARN_CACHE_FOLDER` on the main checkout's cache),
     `scripts/implement-evidence.sh` (always-on
     `yarn turbo run type-check --filter=@calcom/web`)
   - Verified by: `./scripts/issue-to-pr.test.sh` (fake `yarn` records the install
     and the type-check call), then one real
     `./scripts/implement-evidence.sh` run against a worktree of this branch

5. **Three phases, three sessions, to a PR from the agent's draft** — proves the
   harness runs Research → Plan → Implement as separate headless sessions, each
   leaving a committed gate file, and opens the PR with the skill's own body
   - `.claude/skills/implement-task/headless.md` (new), `.claude/skills/implement-task/SKILL.md`,
     `scripts/issue-to-pr.sh` (phase loop, spec folder from the added
     `gates/1-research.md`, body = draft + gate links + evidence block)
   - Verified by: `./scripts/issue-to-pr.test.sh` with a phase-aware fake `claude`
     — three sessions in order, each with `--headless --phase <n>`, phases 2–3
     given the spec path, body holds the draft, the gate links and the block;
     `git diff main -- .claude/skills/implement-task/phases/` is empty

6. **A stopped sequence is red, and says where it stopped** — proves a failed
   session, a missing gate file or `Outcome: blocked` ends the sequence and
   reaches the PR as red evidence
   - `scripts/issue-to-pr.sh` (stop conditions), `scripts/implement-evidence.sh`
     (`phases`, aggregate `agent`, `spec`), `scripts/implement-verdict.sh`
     (per-phase table, a reason per stopped phase),
     `docs/harness/implement-evidence-schema.md`
   - Verified by: `./scripts/implement-verdict.test.sh` (fixtures: all continued,
     one blocked, one missing outcome) and `./scripts/issue-to-pr.test.sh` (phase 1
     fails → no later sessions; phase 2 blocked → no phase 3, draft PR red;
     no gate file → stops)

## In Progress

## Blocked

## Next Steps

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
- Slice 3 done: the agent session gets an explicit allow list and a deny list
  (`git push`, `gh pr`); `headless-task.sh` without the new flags is unchanged.
  Next: slice 4, real install and type-check in the worktree.
- Slice 4 done: the worktree installs from this checkout's cache (47s real run;
  `node_modules/@calcom/lib -> ../../packages/lib` resolves inside the worktree),
  and the collector always runs the `@calcom/web` type-check (confirmed real via
  `--dry=json`: `tsc --pretty --noEmit`; real run exit 0 in 51s). The real run
  showed biome exiting 0 after checking 0 files when nothing changed is a file it
  reads; the collector now records that as not run (`null`, red).
- #27 planned on `feat/implement-task-headless`, cut from `origin/main` after #34
  merged. Base branch: `main` (confirmed at the Phase 2 gate).
- Slice 5 done: three headless sessions in order, spec folder found from the
  added `gates/1-research.md`, PR body = agent draft + gate links + evidence (46
  orchestrator checks). The collector's `--agent-summary` became `--phases` and
  `--spec`, with `agent` now the sum, so part of slice 6's evidence work landed
  here. Next: slice 6, stop conditions, verdict reasons, schema doc.
- Slice 6 done: the loop stops at the first failed, blocked or gate-less phase;
  the verdict gives one reason per stopped phase plus one for the phases that
  never ran, and renders a per-phase table (21 verdict, 61 orchestrator checks).
- From slice 5 until this fix the orchestrator test exited 1 before its last
  section: with no `--phase` in the prompt, the fake `claude` matched an empty
  `FAKE_FAIL_PHASE` and failed, and `set -e` ended the script. The check counts
  quoted for slice 5 were real, but the three `headless-task.sh` checks did not
  run. Fixed in the fake; both suites now exit 0.
