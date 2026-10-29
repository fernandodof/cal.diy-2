# Issue-to-PR Harness Design

Tracks [#24](https://github.com/fernandodof/cal.diy-2/issues/24), the tracer
bullet of the [#23](https://github.com/fernandodof/cal.diy-2/issues/23) PRD.

## Overview

One command takes a GitHub issue number and ends in a **draft** pull request whose
body carries evidence the harness gathered itself. It runs `/implement-task` in a
single headless session inside a fresh git worktree, then — without trusting
anything the agent reported — re-runs the checks, judges the result, pushes the
branch and opens the PR.

## Problem Statement

`scripts/headless-task.sh --issue 11` produced correct tests but no PR: under
`--permission-mode acceptEdits` the session was denied `yarn test` and `gh`, so it
never verified the work and said so (`.claude/headless-runs/issue-11/result.md`).
Even when an agent does get to a PR, any claim in its body about checks is written
by the model that did the work.

## User Stories

- As the repo owner, I want one command with an issue number to end in a draft PR,
  so that I do not drive each step by hand.
- As the repo owner, I want each run in its own worktree, so that my checkout is
  never touched.
- As a reviewer, I want every check result in the PR to come from the harness
  re-running it, so that the evidence can be trusted.
- As a reviewer, I want a red run to still produce a draft PR labelled
  `agent:needs-help`, so that partial work is easy to pick up.

## Technical Design

### Database Changes

None.

### API Changes

None in the app. The new surface is three scripts and one document format.

**Pipeline**, modelled on the `pr-evidence.sh` → `pr-self-approval.sh` split
(`scripts/pr-self-approval.sh:8-12`): gathering facts and judging them are
separate programs, and the judge is pure.

```
issue-to-pr.sh N
  ├─ gh issue view N                      (title/body/url/author)
  ├─ git worktree add <wt> -b agent/issue-N main
  ├─ yarn install --immutable in <wt>     (shared cache, see Edge Cases)
  ├─ headless-task.sh --workdir <wt> --allowed-tools … --disallowed-tools …
  │     prompt: run /implement-task on the issue, headless rules (below)
  ├─ implement-evidence.sh --worktree <wt> --base main …  → implement-evidence/1 JSON
  ├─ implement-verdict.sh --evidence …    → {verdict, labels, evidence_block}
  ├─ git push -u origin agent/issue-N     (the harness pushes, not the agent)
  ├─ gh label create … (idempotent)
  └─ gh pr create --draft --base main …   body = agent summary + evidence block
```

**Headless rules for the tracer.** `/implement-task` has no headless mode yet
(that is #27). The prompt the harness sends tells the agent: treat every gate as
approved, the base is `main`, commit each slice, and **stop after the last
commit** — do not push and do not open a PR. Tool permissions enforce the last
part rather than trusting the prompt.

**Tool allowlist** passed through `--allowedTools`: `Read`, `Edit`, `Write`,
`Glob`, `Grep`, `Skill`, `Bash(yarn test:*)`, `Bash(yarn biome:*)`,
`Bash(yarn turbo run type-check:*)`, `Bash(git status:*)`, `Bash(git diff:*)`,
`Bash(git log:*)`, `Bash(git add:*)`, `Bash(git commit:*)`, `Bash(ls:*)`,
`Bash(cat:*)`, `Bash(grep:*)`, `Bash(find:*)`, `Bash(gh issue view:*)`.
`--disallowedTools` additionally names `Bash(gh pr:*)` and `Bash(git push:*)`, so a
permissive mode can never re-enable them.

**`implement-evidence/1`** (documented in `docs/harness/implement-evidence-schema.md`
beside `pr-evidence/1`):

```jsonc
{
  "schema": "implement-evidence/1",
  "collected_at": "…",
  "issue":  { "number": 24, "url": "…", "title": "…", "author": "fernandodof" },
  "base_ref": "main",
  "merge_base": "…",            // null if unresolvable
  "branch": "agent/issue-24",
  "head_sha": "…",
  "commits": 3,                 // commits on the branch since merge_base
  "agent":  { "status": "completed", "turns": 40, "cost_usd": 1.2 },  // headless summary.json; null if missing
  "diff":   { "files_changed": 4, "insertions": 120, "deletions": 3, "changed_files": ["…"] },
  "checks": [
    { "name": "type-check", "command": "yarn turbo run type-check --filter=@calcom/web",
      "source": "always", "exit_code": 0, "log_tail": "…" },
    { "name": "biome", "command": "yarn biome check <changed files>",
      "source": "always", "exit_code": 0, "log_tail": "…" }
  ]
}
```

**Judge rules** (all must hold for green): schema is `implement-evidence/1`
(otherwise exit 2, no verdict); `merge_base`, `diff`, `agent` are non-null;
`agent.status == "completed"`; `commits > 0`; at least one check reported; every
check has `exit_code == 0`. Red verdict carries `labels: ["agent:needs-help"]` and
the list of reasons. The rendered block is wrapped in
`<!-- evidence:start -->` / `<!-- evidence:end -->`.

### Files

| File | Change |
|---|---|
| `scripts/issue-to-pr.sh` | **new** — orchestrator |
| `scripts/implement-evidence.sh` | **new** — collector; git + re-run checks, no decisions |
| `scripts/implement-verdict.sh` | **new** — pure judge/renderer, no I/O beyond stdin/stdout |
| `scripts/headless-task.sh` | add `--workdir`, `--allowed-tools`, `--disallowed-tools`; default behaviour unchanged (today it runs in the caller's cwd with `--add-dir "$REPO_ROOT"`, `scripts/headless-task.sh:86-92`) |
| `docs/harness/implement-evidence-schema.md` | **new** — the schema, beside `pr-evidence-schema.md` |
| `scripts/implement-verdict.test.sh` | **new** — fixture tests, style of `scripts/pr-self-approval.test.sh` |
| `scripts/issue-to-pr.test.sh` | **new** — fake `claude`/`gh` on `PATH`, real git in a temp repo |

### UI Changes

None.

## Edge Cases

- **Worktree dependencies.** `nodeLinker: node-modules` (`.yarnrc.yml`) and the
  workspace links in `node_modules/@calcom/` are relative symlinks
  (`alby -> ../../packages/app-store/alby`). Symlinking the main checkout's
  `node_modules` into the worktree would make tests resolve `@calcom/*` to the
  **main checkout's** sources — the evidence would test the wrong code. The
  worktree therefore runs its own `yarn install --immutable`, with
  `YARN_CACHE_FOLDER` pointed at the main checkout's `.yarn/cache` (3,586 entries;
  `enableGlobalCache: false`) so it does not re-download.
- **`yarn lint` is not biome.** `package.json:62` makes it `turbo lint`; the
  collector calls `yarn biome check <files>` directly on changed files.
- **No changed files** → biome is skipped and recorded with `exit_code: null`,
  which the judge reads as red (along with `commits == 0`).
- **Branch already exists** → environment error (exit 2) in this slice; resuming
  is #32.
- **Agent session fails or hits max turns** → the collector still runs; the judge
  goes red on `agent.status`; a draft PR is still opened if there is at least one
  commit. With zero commits there is nothing to push: exit with the red code and
  no PR.
- **Log tails** are capped (last 40 lines) so the PR body stays readable.
- **Worktree location** is outside the repo, so the main checkout's tooling never
  walks into it: `${ISSUE_TO_PR_WORKTREE_DIR:-$REPO_ROOT/../<repo>-worktrees}/issue-N`.
  It is left in place after the run for inspection. Run outputs stay in the
  existing, gitignored `.claude/headless-runs/issue-N/` (`.gitignore:110`).

## Out of Scope

- Trust and ambiguity gates (#25), base override (#26), per-phase sessions and
  `/implement-task --headless` (#27), declared verification (#28), acceptance
  criteria (#29), review phase (#30), budgets (#31), re-runs (#32).
- Exit codes beyond today's convention: `0` = green PR, `1` = red (PR opened or
  not), `2` = usage/environment. The richer set lands with #25.
- **Constraint shaping this design** — `specs/README.md`: a PR must be reviewable
  in under 10 minutes, max 5–7 files excluding tests, max 500 lines. This slice is
  5 non-test files; the line budget is the risk, so the scripts stay minimal and
  anything not needed for the green/red path is deferred.

---

# Increment: headless mode, one session per phase (#27)

Tracks [#27](https://github.com/fernandodof/cal.diy-2/issues/27). Builds on the
tracer bullet above, now merged (#34).

## Overview

`/implement-task` gains a headless mode in which no gate waits: each gate writes a
summary file to `specs/<slug>/gates/` and the phase ends. The harness runs
Research, Plan and Implement as **three separate** headless sessions, stops the
sequence when a phase fails, and opens the PR with the agent's body draft
followed by the harness's evidence block. The interactive flow is unchanged.

## Problem Statement

The tracer runs `/implement-task` in one session with a prompt that says "treat
every gate as approved" (`scripts/issue-to-pr.sh:80-86`). The skill's own design
— "each phase writes a file; the next phase reads that file and nothing else"
(`.claude/skills/implement-task/SKILL.md`) — is not honoured: one context carries
all three phases. The gates' content is lost instead of reaching the reviewer, and
the PR body is the agent's free-form closing message (`result.md`), not the
skill's PR body template (`phases/3-implement.md:81-107`).

## Technical Design

### Skill: headless mode

A new `.claude/skills/implement-task/headless.md`, linked from `SKILL.md`, holds
every headless rule. The three phase files are **not edited**, so the interactive
flow cannot drift. Invocation:

```
/implement-task --headless --phase <1|2|3> <issue URL>
```

Rules the file states:

- **Gates write instead of waiting.** Each phase ends by writing
  `specs/<slug>/gates/<n>-<phase>.md` and committing it with the phase's handoff
  file, then stops. Contents:
  - Phase 1: the Overview, the file list, and each open question **with the
    assumption made in place of an answer**.
  - Phase 2: the numbered slices and the base (as given by the harness).
  - Phase 3: `git diff <base> --stat`.
- **Every gate file starts with `Outcome: continue` or `Outcome: blocked`.**
  Blocked is for the cases where the interactive flow says "stop and surface it"
  (e.g. a task contradicting a constraint, `phases/1-research.md` step 5): the
  file says why, and the phase stops.
- **No branching.** The harness has already created and checked out the working
  branch; Phase 2's "branch from the base" step is skipped, its commit is not.
- **The base is given**, not asked: the prompt names it.
- **Phase 3 commits only.** No `git push`, no `gh pr create` (both on the
  harness's deny list). It writes the PR body draft, from the template in
  `phases/3-implement.md`, to `.claude/headless-runs/pr-body.md` in the worktree —
  gitignored (`.gitignore:110`), so it is never committed.
- **Locating the spec.** Phase 1 may extend an existing spec folder (step 1 of
  `phases/1-research.md`) rather than create one, so the slug is the agent's
  choice. The harness finds it afterwards from git: the folder whose
  `gates/1-research.md` the branch added. Phases 2 and 3 are told that path.

### Orchestrator

```
for phase in 1-research 2-plan 3-implement:
  headless-task.sh --run-id issue-N/<phase> --workdir <wt> … 
      "/implement-task --headless --phase <n> <issue url> [--spec specs/<slug>]"
  stop if: session failed | gate file missing | gate Outcome: blocked
  after phase 1: resolve <slug> from the branch's added gates/1-research.md
```

The collector, verdict, push and PR steps run after the loop exactly as today,
whether it completed or stopped. The PR body becomes: `Closes #N`, the agent's
`pr-body.md` draft (or a one-line note that there is none), a link list to the
committed gate files, the evidence block, the footer.

### Evidence (`implement-evidence/1`, additive)

- New `phases`: `[{phase, status, turns, cost_usd, outcome}]`, one per session
  started, in order. `outcome` is the gate file's `continue` / `blocked`, or
  `null` if the file is missing.
- `agent` stays, now the aggregate: `completed` only when all three phases ran,
  completed, and continued; turns and cost summed. The verdict needs no new rule
  for a stopped sequence, and a v1 reader keeps working.
- New `spec`: the resolved `specs/<slug>` path, or `null`.

The verdict renders a per-phase table, and a red reason per stopped phase.

### Files

| File | Change |
|---|---|
| `.claude/skills/implement-task/headless.md` | **new** — every headless rule |
| `.claude/skills/implement-task/SKILL.md` | a short "Headless mode" section linking it |
| `scripts/issue-to-pr.sh` | three sessions, stop conditions, slug resolution, PR body from the draft |
| `scripts/implement-evidence.sh` | `phases`, aggregate `agent`, `spec` |
| `scripts/implement-verdict.sh` | per-phase table and reasons |
| `docs/harness/implement-evidence-schema.md` | the new fields |
| `scripts/issue-to-pr.test.sh`, `scripts/implement-verdict.test.sh` | phase-aware fake `claude`; new cases |

Six non-test files, inside `specs/README.md`'s 5–7.

## Edge Cases

- **Phase 1 adds no `gates/1-research.md`** → `outcome: null`, the sequence stops,
  `spec: null`. With no commits the existing no-PR path applies.
- **Two spec folders gain a `gates/1-research.md`** → ambiguous; treated as missing.
- **A session completes but its gate says blocked** → stops; the gate file is
  committed, so the draft PR carries the reason.
- **No `pr-body.md`** (Phase 3 never ran or skipped it) → the body says so; the
  evidence block is still there.
- **Per-phase run outputs** go to `.claude/headless-runs/issue-N/<phase>/`; the
  issue-level files (`issue.json`, `evidence.json`, `pr-body.md`) stay one level up.

## Out of Scope

- Per-phase turn caps and the cost cap (#31) — each session keeps
  `HEADLESS_TASK_MAX_TURNS`.
- Resuming from `## Status` (#32), the review phase (#30).
- **Constraint shaping this design** — the merged harness denies the agent
  `git push` (`scripts/issue-to-pr.sh`, `DISALLOWED_TOOLS`; ADR in #24's design).
  #27's text says headless Phase 3 "commits, pushes"; this design keeps the push
  with the harness, as #24 settled.

---

# Increment: declared verification commands (#28)

Tracks [#28](https://github.com/fernandodof/cal.diy-2/issues/28). Builds on #27
(merged in #35).

## Overview

Phase 2 declares the commands that verify its slices, in a `## Verification`
section of `implementation.md`. After the agent finishes, the collector runs each
declared command that passes the allowlist, alongside the always-on type-check and
biome. A command that fails the allowlist is never executed: it is recorded under
`rejected_commands` and turns the verdict red. A missing or empty section is a
`null` fact, so red too.

## Problem Statement

The always-on checks cannot know which tests prove *this* change. Phase 2 already
names them per slice ("Verified by: `yarn test …`", `phases/2-plan.md:41-48`), but
as prose the collector cannot run. #11 is the example of the gap: the issue named
its verification command, and nothing ran it.

## Technical Design

### The section

`specs/_templates/implementation.md` gains, after `## Next Steps`:

````markdown
## Verification

```sh
```
````

One command per line inside the first fenced block under the heading; blank lines
and lines starting with `#` are ignored. Interactive Phase 2 may leave it empty —
nothing reads it outside the harness, so the interactive flow is unchanged.
`headless.md`'s Phase 2 bullet gains: list in it the `yarn test <path>` command
for every test file the slices name.

### The allowlist

Exactly one shape: **`yarn test <path> [<path> …]`**, where each path

- matches `^[A-Za-z0-9_@./-]+$` (no spaces, quotes, `$`, `;`, `|`, `&`, globs),
- does not start with `-` or `/`, and has no `..` segment,
- ends in `.test.ts` or `.test.tsx`.

Nothing else is allowed — notably not `yarn turbo run type-check --filter=<pkg>`:
turbo exits 0 for a task that does not exist (`phases/3-implement.md:61-64`), so a
declared filter naming a package without the task would read as a pass. The
`@calcom/web` type-check that does cover those packages is already always-on.

**Never through a shell.** An accepted line is split on whitespace into an argv
and passed to the same `run_check` the always-on checks use (`"$@"`, no `eval`,
no `bash -c`), so even a line that slipped past the pattern could not expand,
redirect or chain.

### Evidence (`implement-evidence/1`, additive)

- `checks[]` entries for declared commands carry `source: "declared"`, named
  `test: <first path>` (+ ` (+N)` for more).
- New `declared_commands`: the accepted lines, in order; `null` when the section
  is missing, the block is absent or empty, or there is no spec.
- New `rejected_commands`: `[{command, reason}]`, never executed; `[]` when none.

### Verdict

- `declared_commands == null` → red: "verification: Phase 2 declared no commands".
- Each rejected command → red: "verification: rejected `<cmd>` (<reason>)".
- Declared checks are judged like always-on ones (non-zero or null exit → red).
- The block's Checks table already shows `source`; rejected commands get their own
  list under it.

### Files

| File | Change |
|---|---|
| `specs/_templates/implementation.md` | the `## Verification` section |
| `.claude/skills/implement-task/headless.md` | Phase 2 fills it |
| `scripts/implement-evidence.sh` | parse, allowlist, run declared checks, two new fields |
| `scripts/implement-verdict.sh` | two rules, rejected-commands list |
| `docs/harness/implement-evidence-schema.md` | the new fields and the allowlist |
| `scripts/implement-verdict.test.sh`, `scripts/issue-to-pr.test.sh` | fixtures; fake Phase 2 declares commands; a rejected command is proven not to run |

Five non-test files, no orchestrator change: the collector already gets `--spec`.

## Edge Cases

- **A path that matches no test passes vitest.** `vitest.config.mts:119` sets
  `passWithNoTests: true`; a real `yarn test packages/lib/does-not-exist.test.ts`
  exits 0 with `No test files found, exiting with code 0`. So the collector
  (a) checks every declared path is a file in the worktree before running —
  any missing → the check is recorded `exit_code: null`, "not run: <path> does not
  exist", and never executed; and (b) records `exit_code: null` when vitest exits 0
  but its output says `No test files found` (a file that exists but no vitest
  project includes). Both read as red. Like turbo's missing task, a check that
  exits 0 without running is not a pass.
- **Several fenced blocks** under the heading → only the first is read.
- **Spec without `implementation.md`** (Phase 2 never ran) → `null`, red; it is
  already red for the stopped phase, and both reasons are listed.
- **The same command twice** runs once.

## Out of Scope

- Any command shape beyond `yarn test` — widening the allowlist is a policy change
  for its own issue.
- Acceptance criteria → tests mapping (#29), which consumes these results.

---

# Increment: acceptance criteria mapped to tests (#29)

Tracks [#29](https://github.com/fernandodof/cal.diy-2/issues/29). Builds on #28
(merged in #36).

## Overview

Phase 1 writes the issue's requirements as an `## Acceptance Criteria` checklist
in `design.md`, each item tagged with the test that proves it. The collector runs
the declared tests with vitest's JSON reporter added, and records for each
criterion whether its test was found in that run and what status it had. The
verdict is red for any criterion without a found, **passed** test, and the block
shows the criteria as a table.

## Problem Statement

#28 proves the declared test files pass, not that they test what the issue asked.
A green file can still leave a requirement uncovered, and a file exit code cannot
see inside it: a real run of a probe with `it.skip` and `it.todo` beside one
passing test **exits 0** (`yarn test`, 2026-10-29), while the JSON reporter marks
them `skipped` and `todo`.

## Technical Design

### The section and its tag

`specs/_templates/design.md` gains an optional section after `## User Stories`:

```markdown
## Acceptance Criteria

- [ ] <what must be true> — `<path/to/file.test.ts>` › <full test name>
```

The tag is everything after the last ` — `: a backticked test file path, ` › `,
then the test's **full name** as vitest reports it (`fullName`: the `describe`
titles and the `it` title joined by spaces — e.g. `uniqueBy should remove
duplicates based on single key` for `packages/lib/array.test.ts`). An item without
a tag is untagged. Interactive Phase 1 may leave the section out; `headless.md`'s
Phase 1 bullet gains: one criterion per requirement in the issue, each tagged;
Phase 2 declares every tagged file.

### Collector

- Each declared command runs with
  `--reporter=default --reporter=json --outputFile.json=<tmp>` appended by the
  collector — collector-owned flags, so the allowlist on what Phase 2 writes is
  unchanged. The console output still feeds `log_tail` and the
  `No test files found` rule (confirmed: both reporters run together and the JSON
  lands in the file, `packages/lib/array.test.ts` real run).
- The JSON reports' `testResults[].name` are absolute; they are made relative to
  the worktree and keyed by `(file, fullName)` → `status`.
- New `criteria` (`null` if the section is missing or has no items, or there is
  no spec):

```jsonc
"criteria": [
  { "text": "…", "test_file": "packages/lib/x.test.ts", "test_name": "x does y",
    "test_found": true,          // (file, name) appeared in the collector's run
    "test_status": "passed",     // passed | failed | skipped | todo | null if not found
    "declared": true }           // test_file is among the declared commands' paths
]
```

  Untagged items have `test_file`, `test_name` and `test_status` `null` and
  `test_found: false`.

### Verdict

- `criteria == null` → red: "criteria: Phase 1 recorded no acceptance criteria".
- Per criterion, the first that applies:
  - untagged → "criterion `<text>`: no test named";
  - not `declared` → "criterion `<text>`: `<file>` is not among the declared tests";
  - not `test_found` → "criterion `<text>`: `<name>` was not found in `<file>`";
  - `test_status != "passed"` → "criterion `<text>`: `<name>` was `<status>`".
- Block gains a Criteria table: criterion, test, status (✅ only for `passed`).

### Files

| File | Change |
|---|---|
| `specs/_templates/design.md` | the optional `## Acceptance Criteria` section and tag format |
| `.claude/skills/implement-task/headless.md` | Phase 1 fills it; Phase 2 declares every tagged file |
| `scripts/implement-evidence.sh` | JSON reporter on declared runs, parse criteria, `criteria` field |
| `scripts/implement-verdict.sh` | criteria rules and table |
| `docs/harness/implement-evidence-schema.md` | `criteria` and the tag format |
| `scripts/implement-verdict.test.sh`, `scripts/issue-to-pr.test.sh` | fixtures; fake `yarn test` writes a JSON report |

Five non-test files.

## Edge Cases

- **A tagged file not declared** is not run by the harness — the criterion is red
  with its own reason rather than the collector widening what it runs.
- **Two tests with the same full name in one file** → found if any matches; the
  status is `passed` only if all matching ones passed.
- **A declared run that crashes before reporting** (no JSON file) → its criteria
  are not found, red; the check itself is already red on exit code.
- **Name matching is exact** (after trimming). A renamed test reads as not found —
  that is the point.

## Out of Scope

- Judging whether a test really proves its criterion — the review phase (#30).
