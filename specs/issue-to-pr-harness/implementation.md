# Issue-to-PR Harness Implementation

## Status: planned

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

7. **Declared tests run and reach the evidence** — proves a `yarn test` command
   Phase 2 writes into `## Verification` is run by the collector, not the agent,
   and shows in the PR as a `declared` check
   - `specs/_templates/implementation.md`, `.claude/skills/implement-task/headless.md`,
     `scripts/implement-evidence.sh` (parse the first fenced block, the `yarn test`
     allowlist, run as argv, `declared_commands`), `scripts/implement-verdict.sh`
     (`declared_commands: null` is red)
   - Verified by: `./scripts/issue-to-pr.test.sh` — fake Phase 2 declares a test the
     fake Phase 3 adds; fake `yarn` records it run in the worktree; evidence has a
     `declared` check; a Phase 2 that declares nothing is red; and
     `./scripts/implement-verdict.test.sh` for the null rule

8. **Commands that would not really verify anything are red** — proves rejected
   commands never execute, and a declared test that matches nothing is not a pass
   - `scripts/implement-evidence.sh` (`rejected_commands` with reasons; missing
     path and `No test files found` → `exit_code: null`), `scripts/implement-verdict.sh`
     (one reason per rejection, rejected list in the block),
     `docs/harness/implement-evidence-schema.md`
   - Verified by: `./scripts/issue-to-pr.test.sh` — a declared
     `yarn test a.test.ts; touch pwned` and a `curl …` line are rejected and
     `pwned` never appears; a missing path is never run; fake `yarn` printing
     `No test files found` with exit 0 is red — and verdict fixtures for each

9. **Criteria reach the evidence with their tests' real status** — proves a
   criterion Phase 1 tags is looked up in the collector's own JSON report of the
   declared run and shown in the PR
   - `specs/_templates/design.md`, `.claude/skills/implement-task/headless.md`,
     `scripts/implement-evidence.sh` (JSON reporter flags on declared runs, parse
     `## Acceptance Criteria`, `criteria`), `scripts/implement-verdict.sh`
     (`criteria: null` is red, criteria table)
   - Verified by: `./scripts/issue-to-pr.test.sh` — fake Phase 1 tags a test, fake
     `yarn test` writes a JSON report to the path it is given; the evidence has the
     criterion found and `passed`, the body has the table; a design with no
     criteria is red — and a verdict fixture for the null rule

10. **A criterion without a passing test is red, and says why** — proves every way
    a criterion can go uncovered names itself in the PR
    - `scripts/implement-verdict.sh` (untagged, not declared, not found, not
      passed), `scripts/implement-evidence.sh` (duplicate names),
      `docs/harness/implement-evidence-schema.md`
    - Verified by: verdict fixtures for each reason and for skipped/todo; the
      orchestrator with a fake report marking the tagged test `skipped` while the
      run exits 0 → red

11. **An untrusted author is refused before anything happens** — proves the
    harness exits 3 on an issue not written by the repo owner, touching nothing,
    and proceeds with `--trust`
    - `scripts/issue-to-pr.sh` (`--trust`, owner from `gh repo view`, exit 3,
      usage block lists all four exit codes)
    - Verified by: `./scripts/issue-to-pr.test.sh` — another author → exit 3, no
      `gh` call besides the reads, no worktree, no branch, no label created;
      `--trust` → the normal green run

12. **An ambiguous issue is sent back with the judge's reasoning** — proves a
    score ≤ 1 comments, labels and stops before any branch, and a clear issue
    sheds a stale label and proceeds
    - `scripts/issue-to-pr.sh` (`ISSUE_TO_PR_SCORER`, labels moved before the
      gate, comment + label + exit 3, null score → exit 2, clear path removes
      `agent:needs-clarification`)
    - Verified by: `./scripts/issue-to-pr.test.sh` with a fake scorer — score 1 →
      one comment carrying the reasoning, the label, exit 3, no worktree; score 0
      likewise; score 2 → proceeds; a parse failure → exit 2, no comment; a clear
      issue that carried the label has it removed

13. **An issue's base reaches every place the base is used** — proves a
    `base:<branch>` label or `Base: <branch>` body line moves the worktree cut, the
    phase prompts, the evidence diff and the PR to that branch
    - `scripts/issue-to-pr.sh` (resolve from labels and body; default `main`)
    - Verified by: `./scripts/issue-to-pr.test.sh` — the sandbox origin gains a
      `release` branch with a commit `main` lacks; with the label, then with the
      body line: the worktree contains that commit, every phase prompt says
      `--base release`, `evidence.json` has `base_ref: release`, and the PR is
      `--base release`; with neither, all of it is `main`

14. **A base that cannot be right is refused before anything starts** — proves a
    conflicting, malformed, missing or self-referential base exits 2 with no
    scoring, comment, worktree or PR
    - `scripts/issue-to-pr.sh` (conflict check, charset + `git check-ref-format`,
      `git ls-remote`, not `agent/issue-N`)
    - Verified by: `./scripts/issue-to-pr.test.sh` — label `base:release` with body
      `Base: main`; `Base: x;rm`; `base:nope`; `base:agent/issue-7` — each exit 2,
      the scorer never called, no worktree, no PR

15. **Every phase runs inside its caps** — proves each session is started with
    its own turn cap and with only what is left of the cost cap, and that the
    evidence shows both
    - `scripts/headless-task.sh` (`--max-budget-usd`), `scripts/issue-to-pr.sh`
      (per-phase `--max-turns`, remaining budget, cap validation, `budget.json`),
      `scripts/implement-evidence.sh` (`budget`, `phases[].subtype`),
      `scripts/implement-verdict.sh` (Budget row)
    - Verified by: `./scripts/issue-to-pr.test.sh` — the fake `claude` logs each
      call's flags: turns 30/15/80, budgets 5, then 5 minus each phase's cost; env
      overrides change both; a non-numeric cap exits 2 before anything starts

16. **Hitting a limit stops the run and says which** — proves a spent budget, a
    turn cap or a blocked plan ends the sequence on the honest-failure path
    - `scripts/issue-to-pr.sh` (stop on spent budget, on `## Status: blocked`),
      `scripts/implement-evidence.sh` (`plan_status`, `exceeded`),
      `scripts/implement-verdict.sh` (three rules),
      `docs/harness/implement-evidence-schema.md`
    - Verified by: `./scripts/issue-to-pr.test.sh` — a phase costing more than the
      cap → no next phase, red draft PR naming the cost; `error_max_turns` in
      Plan → no Implement, the reason names the cap; a plan at `## Status:
      blocked` with `Outcome: continue` → stops; verdict fixtures for each rule

17. **A review runs after Implement and its findings reach the PR** — proves a
    fourth session reviews the branch, records findings by axis and severity, and
    a run without a review is red
    - `.claude/skills/implement-task/headless.md` (Phase 4), `scripts/issue-to-pr.sh`
      (review session with `Agent` added, 30-turn cap), `scripts/implement-evidence.sh`
      (`review`, four phases make a complete run), `scripts/implement-verdict.sh`
      (null-review rule, findings by axis in the block)
    - Verified by: `./scripts/issue-to-pr.test.sh` — the fake Phase 4 writes
      `review.json` and its gate; the review prompt names `origin/main`, the spec
      and the issue; only the review session's allowlist has `Agent`; findings
      render by axis; no `review.json` → red; a stopped earlier phase → no review —
      and verdict fixtures

18. **Spec findings get exactly one fix round** — proves a missing or wrong
    requirement triggers one fix session and nothing else does
    - `.claude/skills/implement-task/headless.md` (fix round),
      `scripts/issue-to-pr.sh` (trigger, fix session, 40-turn cap),
      `scripts/implement-evidence.sh` (`fix` phase, `fix_round_applied`),
      `docs/harness/implement-evidence-schema.md`
    - Verified by: `./scripts/issue-to-pr.test.sh` — a `missing` spec finding →
      exactly one fix session and no second review; `wrong` likewise; standards-only
      and creep-only findings → none; a failed fix session → red

19. **The agent's handoff files reach the harness from a path it can write** —
    proves Phase 3's `pr-body.md` and Phase 4's `review.json` go to and are read
    from `.agent-handoff/`, gitignored, and nothing still names the old path
    - `.gitignore`, `.claude/skills/implement-task/headless.md`,
      `scripts/issue-to-pr.sh`, `scripts/implement-evidence.sh`,
      `docs/harness/implement-evidence-schema.md`, `scripts/issue-to-pr.test.sh`
    - Verified by: `./scripts/issue-to-pr.test.sh`. The fake `claude` writes both
      files to `.agent-handoff/`, and the existing body, review and fix-round
      checks still pass. New checks: `headless.md` names
      `.agent-handoff/pr-body.md` and `.agent-handoff/review.json` and never
      `.claude/headless-runs`, and `git check-ignore` matches both files.
      `./scripts/implement-verdict.test.sh` is unchanged and still passes.

20. **The agent's code passes the evidence's biome check before it is
    committed**. This proves Phase 3 and the fix round are told to run the
    command the evidence judges them by, and that their session is allowed to
    run it.
    - `.claude/skills/implement-task/phases/3-implement.md`,
      `.claude/skills/implement-task/headless.md`, `scripts/issue-to-pr.test.sh`
    - Verified by: `./scripts/issue-to-pr.test.sh`. New checks:
      `phases/3-implement.md` names `yarn biome check --write`, the fix round in
      `headless.md` verifies as Phase 3 does, and `issue-to-pr.sh`'s allowlist
      has `Bash(yarn biome:*)`. All existing checks still pass. The real check
      is the #11 rerun after merge.

## In Progress

## Blocked

## Next Steps

21. **A type error in a changed file that web doesn't import turns the verdict
    red**. This proves the collector type-checks each touched project and judges
    only the changed files: a clean file is green even though the project has
    other errors, an error in the file is red, and a file with no project is
    "not covered".
    - `scripts/implement-evidence.sh`, `docs/harness/implement-evidence-schema.md`
    - Verified by: `./scripts/issue-to-pr.test.sh`. The fake `yarn tsc` prints
      error lines. Checks: one error in a changed file → `type-check:
      packages/lib` exited 1 and the PR is red with that line; errors only in
      other files → exit 0, green, with the "elsewhere" count; two changed files
      in one project → one `tsc` run; a changed `apps/web` file → no extra run;
      a `.ts` file with no project → `type-check: not covered`, red; a `tsc` that
      exits non-zero with no error lines → not run.

22. **The agent can type-check what it changed**. This proves the rules tell
    Phase 3 to run the same `tsc` command and that the session allows it.
    - `scripts/issue-to-pr.sh` (allowlist),
      `.claude/skills/implement-task/phases/3-implement.md`
    - Verified by: `./scripts/issue-to-pr.test.sh`. Phase 3's rules name
      `yarn tsc --noEmit -p`; the allowlist has `Bash(yarn tsc --noEmit -p:*)`;
      the rules no longer say web covers `packages/lib`.

23. **The evidence reads cleanly** (#45). Costs show to the cent, commands show
    no temp paths, the run directory holds only the current run's files, and the
    no-draft fallback names the gate file.
    - `scripts/implement-verdict.sh`, `scripts/implement-evidence.sh`,
      `scripts/issue-to-pr.sh`
    - Verified by: `./scripts/implement-verdict.test.sh` (a fixture with costs
      like `0.27312559999999997` renders as `$0.27`) and
      `./scripts/issue-to-pr.test.sh` (no `/tmp`/`/var` paths in the body; a
      stale file in the run directory is gone after a run; the fallback names
      `gates/3-implement.md`).

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
- #28 planned on `feat/declared-verification`, cut from `origin/main` after #35
  merged. Base branch: `main` (confirmed at the Phase 2 gate).
- Slice 7 done: Phase 2's `## Verification` block is parsed, held to the
  `yarn test <path>` allowlist and run as an argv by the collector (68
  orchestrator checks, verdict suite green; both exit 0). Rejections are already
  recorded in `rejected_commands` here; slice 8 makes them red. Next: slice 8.
- Slice 8 done: each rejected command is a red reason and listed as not run; a
  declared test whose file is missing is never run, and an exit 0 with
  `No test files found` is recorded as not run (27 verdict, 79 orchestrator
  checks; both suites exit 0). An injection set — `;`, `$(…)`, `curl`, `..` —
  is rejected and nothing it names is created.
- #29 planned on `feat/acceptance-criteria`, cut from `origin/main` after #36
  merged. Base branch: `main` (confirmed at the Phase 2 gate).
- Slice 9 done: criteria are parsed from `design.md` and looked up by file and
  full name in the declared runs' JSON reports (85 orchestrator, 29 verdict
  checks; both exit 0). The duplicate-name rule (all must pass) landed here with
  the lookup. Found while testing: with no report on disk, the report loop's last
  `[[ -f ]]` failed the pipeline under `pipefail`; now an explicit `if`.
  Next: slice 10, the per-criterion reasons.
- Slice 10 done: each uncovered criterion gives one reason — untagged, not
  declared, not found, or reported as failed/skipped/todo (36 verdict, 93
  orchestrator checks; both exit 0). A skipped tagged test is red although its
  run exits 0, and an undeclared tagged file is never run.
- #25 planned on `feat/trust-ambiguity-gates`, cut from `origin/main` after #37
  merged. Threshold corrected to "stop at ≤ 1" with the user in Phase 1; #25 and
  #23 edited to match. Base branch: `main` (confirmed at the Phase 2 gate).
- Slice 11 done: an issue not written by the repo owner exits 3 after only the
  two reads (`issue view`, `repo view`); `--trust` runs it (101 orchestrator
  checks, exit 0). Next: slice 12, the ambiguity gate.
- Slice 12 done: a score ≤ 1 comments the judge's reasoning, labels
  `agent:needs-clarification` and exits 3 before any branch; no score is exit 2
  with no comment; a clear issue sheds a stale label (123 orchestrator checks,
  exit 0). Label setup moved up between the gates. The fake `gh` now remembers
  labels it created — with labels set up before the branch check, the test's
  second run would otherwise have recreated them, which real GitHub would not.
- #26 planned on `feat/base-override`, cut from `origin/main` after #38 merged.
  Base branch: `main` (confirmed at the Phase 2 gate).
- Slice 13 done: a `base:` label or `Base:` body line moves the worktree cut, all
  three phase prompts, the evidence diff and the PR to that branch; agreeing
  label and body are one base (129 orchestrator checks, exit 0). Until slice 14,
  conflicting candidates take the first. Next: slice 14, refusing bad bases.
- Slice 14 done: conflicting, malformed (`x;rm`, `a..b`), missing and
  self-referential bases exit 2 before the scorer runs or anything is created
  (142 orchestrator checks, exit 0).
- #31 planned on `feat/budgets`, cut from `origin/main` after #39 merged.
  Base branch: `main` (confirmed at the Phase 2 gate).
- Slice 15 done: sessions start with turn caps 30/15/80 and `--max-budget-usd`
  set to what is left of $5; caps are env-overridable and validated before the
  issue is fetched; the evidence carries `budget` and each phase's `subtype` (153
  orchestrator checks, exit 0). Next: slice 16, stopping on a hit limit.
- Slice 16 done: a spent cost cap stops before the next phase, a turn cap and a
  plan at `## Status: blocked` stop after theirs, each on the red draft-PR path
  with its own reason (41 verdict, 163 orchestrator checks; both exit 0).
- A real probe of `--max-budget-usd` (two Haiku calls) showed decimals work, an
  exhausted budget reports `error_max_budget_usd`, and the CLI checks between
  turns, so a run can end slightly over its cap. The collector now also counts
  that subtype as the cost cap; documented in the schema (165 orchestrator
  checks, exit 0).
- #30 planned on `feat/review-phase`, cut from `origin/main` after #40 merged.
  Base branch: `main` (confirmed at the Phase 2 gate).
- Slice 17 done: a fourth session reviews the branch with `/code-review`, told
  the base, spec and issue up front; only its allowlist has `Agent`; findings
  reach the evidence and the body by axis; a review that recorded nothing is red
  (43 verdict, 175 orchestrator checks; both exit 0). A complete run is now four
  phases and four commits. Next: slice 18, the fix round.
- Slice 18 done: a `missing` or `wrong` spec finding runs exactly one fix
  session (40-turn cap, rest of the budget) and no second review; standards and
  creep findings run none; a failed fix round is red (193 orchestrator checks,
  43 verdict; both exit 0). Found while testing: `n=fix` made the old
  `[[ $n -eq 1 ]]` checks read an unset variable under `set -u`; they now compare
  the phase name. The orchestrator suite now takes over two minutes.
- #51 planned on `fix/agent-handoff-path`, cut from `origin/main` after #41
  merged. Base branch: `main` (confirmed at the Phase 2 gate). Cause found by the
  #33 smoke run (PR #42). Two real-session probes showed that a headless `Write`
  under `.claude/` is denied as a sensitive file, even with an explicit allow
  rule, while `.agent-handoff/` works.
- Slice 19 done: `pr-body.md` and `review.json` move to `.agent-handoff/`, which
  is gitignored, in the rules, the orchestrator, the collector and the schema
  doc. ADR-002 records why an allow rule was not enough (197 orchestrator, 43
  verdict checks; both exit 0). The real check is re-running #11 after merge.
- #44 planned on `fix/agent-runs-biome`, cut from `origin/main` after #52
  merged. Base branch: `main` (confirmed at the Phase 2 gate). Both #11 smoke
  runs failed `biome check` on import order. The pre-commit hook runs
  `biome lint`, which doesn't sort imports.
- Slice 20 done: Phase 3's Verify block now runs `yarn biome check --write` on
  the changed files and says why the hook is not enough. The fix round verifies
  as Phase 3 does (200 orchestrator, 43 verdict checks; both exit 0). The real
  check is re-running #11 after merge.
- #43 planned on `fix/type-check-changed-files`, cut from `origin/main` after
  #55 merged. Base branch: `main` (confirmed at the Phase 2 gate). One PR, three
  slices. Review-size check: 5 non-test files.
