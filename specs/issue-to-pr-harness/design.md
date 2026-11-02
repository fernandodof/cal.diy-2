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

---

# Increment: trust and ambiguity gates (#25)

Tracks [#25](https://github.com/fernandodof/cal.diy-2/issues/25). Builds on the
tracer (#34); independent of #27–#29.

## Overview

Two gates run right after the issue is fetched, before any branch, worktree,
install or agent session exists. The **trust gate** refuses an issue whose author
is not the repo owner unless `--trust` is passed, with no side effects. The
**ambiguity gate** scores the issue with the existing scorer; at **1 or lower**
it comments the judge's reasoning, labels the issue `agent:needs-clarification`
and stops. Exit codes gain a distinct value for "refused".

## Problem Statement

The issue body becomes the agent's prompt, so an issue written by anyone who can
open one is an instruction to an agent with write access to a branch. And an
issue too vague to implement costs a full three-phase run before anyone finds out.

## Technical Design

### Threshold — corrected from the issue

`evals/issue-ambiguity/RUBRIC.md` scores **3 = Unambiguous** down to
**0 = Unactionable**. #25 (and the PRD, #23) said "a score of 2 or higher" stops
the run, which would refuse the clearest issues. Confirmed with the user at this
phase: **stop at a score ≤ 1** (unactionable, highly ambiguous); proceed on 2
(mostly clear) and 3. #25 and #23 were edited to match, with a dated note.

### Order of the gates

1. **Trust** — `gh repo view --json owner` gives the owner; `issue.json`'s
   `author.login` must equal it, or `--trust` was passed. Otherwise print the
   reason and exit **3**. Nothing is written to GitHub, no label is created —
   the check costs nothing, so it runs first.
2. **Labels** — the existing idempotent label setup (`scripts/issue-to-pr.sh`)
   moves up to here, so `agent:needs-clarification` exists before it is used.
3. **Ambiguity** — `"$SCORER" --issue <owner/repo>#<N>` (default
   `evals/issue-ambiguity/score.sh`, overridable as `ISSUE_TO_PR_SCORER` — the
   scorer itself calls `claude -p`, `score.sh:52`, so tests substitute it rather
   than the fake `claude`). Output `{id, score, reasoning}` goes to
   `<run>/ambiguity.json`.
   - `score ≤ 1` → one issue comment (score, label, reasoning, how to proceed),
     `agent:needs-clarification` added, exit **3**.
   - `score == null` (the scorer's `PARSE_FAILURE`) or the scorer failing → exit
     **2**, no comment: a judge that did not answer is an environment problem,
     not a verdict on the issue.
   - `score ≥ 2` → if the issue carries `agent:needs-clarification` from an
     earlier run, remove it; continue.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | draft PR opened, evidence green |
| 1 | red — draft PR opened, or nothing to push |
| 2 | bad usage / environment (unchanged) |
| **3** | **refused** — untrusted author or ambiguous issue; no branch, no PR |

Documented in the script's usage block.

### Files

| File | Change |
|---|---|
| `scripts/issue-to-pr.sh` | `--trust`, both gates, labels moved up, exit 3, usage |
| `scripts/issue-to-pr.test.sh` | fake scorer; `gh repo view`, `issue comment`, `issue edit` in the fake `gh` |

One non-test file.

## Edge Cases

- **The comment is posted once per refused run.** A re-run on an unchanged issue
  posts another — it is a new judgement on the current text, and #32 (re-runs)
  owns deduplication if that proves noisy.
- **`issue.json` gains `labels`** so the clear-path removal does not need a
  second fetch.
- **An issue from another repo** is out of scope for the harness (PRD), so the
  owner is this repo's.

## Out of Scope

- Changing the rubric or the scorer.
- Trust beyond the owner (a list of collaborators) — `--trust` covers it.

---

# Increment: base-branch override from the issue (#26)

Tracks [#26](https://github.com/fernandodof/cal.diy-2/issues/26). Builds on #25
(merged in #38).

## Overview

The base branch stays `main` unless the issue names another, with a
`base:<branch>` label or a `Base: <branch>` line in its body. The harness
resolves it right after the trust gate, refuses a malformed, conflicting or
missing base as an environment error (exit 2) before anything is created, and
otherwise uses it everywhere `main` is used today.

## Problem Statement

This fork has long-lived feature branches (`phases/3-implement.md`, "Never assume
`main`"); the interactive flow asks for the base at Phase 2, but the harness
hardcodes `BASE_REF="main"` (`scripts/issue-to-pr.sh:26`), so an issue that
belongs on a feature branch gets a PR against the wrong one.

## Technical Design

### One variable already carries it

`BASE_REF` is the only source for every base use: the fetch and the worktree cut
(`scripts/issue-to-pr.sh:127,134`), the spec lookup (`:166`), the phase prompts'
`--base` (`:177`), the collector's diff (`:209`) and `gh pr create --base`
(`:255`). Resolving it from the issue is the whole change. Recording it in
`implementation.md` is already done: headless Phase 2 is given `--base` and told
to record it under `## Session Notes` (`.claude/skills/implement-task/headless.md:50`).

### Resolution (after the trust gate, before labels and scoring)

- From labels: every label named `base:<branch>`.
- From the body: every line matching `^Base: *<branch> *$`, the branch optionally
  in backticks.
- No candidates → `main`. All candidates equal → that branch. Different
  candidates → exit 2, naming them: guessing between two bases is how the wrong
  PR gets opened.
- **Validated before use**, since an issue author supplies it and it reaches git
  and the agent's prompt: `^[A-Za-z0-9._/-]+$` **and** `git check-ref-format
  --branch`. git alone is not enough — it accepts `x;rm` (checked).
- **Must exist on the remote**: `git ls-remote --exit-code --heads origin <base>`,
  else exit 2, "no fallback to main".

It runs before the ambiguity gate so a run that cannot succeed costs no judge
call and posts no comment; after the trust gate, because that one writes nothing
and must stay first.

### Files

| File | Change |
|---|---|
| `scripts/issue-to-pr.sh` | resolve, validate and check the base; usage line |
| `scripts/issue-to-pr.test.sh` | a second branch on the sandbox origin; label, body, conflict, malformed and missing cases |

## Edge Cases

- **Label and body agree** → fine; **disagree** → exit 2.
- **`Base:` inside a code block** in the body still matches — line-based, like
  the rest of the harness's parsing. Acceptable: writing that line is a
  deliberate act.
- **A base equal to the working branch** (`agent/issue-N`) → exit 2; it would
  be cut from itself.

## Out of Scope

- A `--base` flag on the harness itself — the issue is the record of intent.

---

# Increment: budgets and blocked-status routing (#31)

Tracks [#31](https://github.com/fernandodof/cal.diy-2/issues/31). Builds on #27
(merged in #35); independent of #25/#26.

## Overview

Each phase session gets its own turn cap and the run a total cost cap of $5,
**enforced inside the sessions**: every phase is started with
`--max-budget-usd` set to what is left of the cap. Hitting a cap, or a plan left
at `## Status: blocked`, stops the remaining phases; the collector still runs,
the evidence records the budget, and the verdict says which limit was hit.

## Problem Statement

Each session today runs to `HEADLESS_TASK_MAX_TURNS` (default 40,
`scripts/headless-task.sh:20`) whatever the phase, and nothing bounds what a run
costs: three phases at 40 turns each have no ceiling. A phase that marks the plan
blocked without also writing `Outcome: blocked` would let the next phase start.

## Technical Design

### Caps and their names

| Variable | Default |
|---|---|
| `HEADLESS_TASK_MAX_TURNS_RESEARCH` | 30 |
| `HEADLESS_TASK_MAX_TURNS_PLAN` | 15 |
| `HEADLESS_TASK_MAX_TURNS_IMPLEMENT` | 80 |
| `HEADLESS_TASK_MAX_COST_USD` | 5 |

`HEADLESS_TASK_*` as #31 asks. The Review cap (30) arrives with the Review phase
in #30; nothing here reserves it.

### Enforcement

- **Turns:** each phase is started with `--max-turns <its cap>` (the runner
  already passes `--max-turns`, `scripts/headless-task.sh:116`).
- **Cost:** `headless-task.sh` gains `--max-budget-usd` (passed through; the CLI
  supports it in `--print` mode, `claude --help`). Before each phase the harness
  computes `remaining = cap − spent so far`; at `remaining ≤ 0` the phase is not
  started; otherwise it is started with `--max-budget-usd remaining`. So the cap
  holds within a session, not only between them. Sums use `jq` (bash has no
  floats).
- **Why a phase stopped** comes from its `summary.json` `subtype`, which each
  phase record now carries: `error_max_turns` is a turn cap. The cost cap counts
  as exceeded when `spent ≥ cap` **or** a session's subtype is
  `error_max_budget_usd`. *Phase 3 probe (two real Haiku calls): decimals are
  accepted; an exhausted budget reports `error_max_budget_usd`; and the CLI
  checks between turns — $0.0017 was spent against a $0.0001 budget — so a run
  can end slightly over its cap.*
- **Blocked plan:** after each phase, a `## Status: blocked` in
  `<spec>/implementation.md` stops the sequence, independently of the gate's
  `Outcome`.

### Evidence (`implement-evidence/1`, additive)

- `phases[].subtype` — the session's subtype.
- `budget`:
  `{cost_cap_usd, spent_usd, turn_caps: {"1-research": 30, …}, exceeded: null | "cost" | "turns:<phase>"}`.
- `plan_status` — the `## Status:` value of `implementation.md`, or `null`.

### Verdict

- `budget.exceeded == "cost"` → "budget: spent $X of the $Y cap".
- `budget.exceeded == "turns:<phase>"` → "budget: <phase> hit its <n>-turn cap".
- `plan_status == "blocked"` → "plan: implementation.md says blocked — see its `## Blocked`".
- The block gains a Budget row: spent / cap, and the turn caps.

These sit beside the per-phase reasons from #27; a turn cap is also a failed
phase there, and both lines are kept — one says *that* it stopped, the other
*why*.

### Files

| File | Change |
|---|---|
| `scripts/headless-task.sh` | `--max-budget-usd` pass-through |
| `scripts/issue-to-pr.sh` | per-phase turn caps, remaining budget, stop on cost or blocked plan, `budget.json` |
| `scripts/implement-evidence.sh` | `budget`, `plan_status`, `phases[].subtype` |
| `scripts/implement-verdict.sh` | three rules, Budget row |
| `docs/harness/implement-evidence-schema.md` | the new fields |

Five non-test files.

## Edge Cases

- **A phase with no summary** counts as $0 spent — the run cannot be charged for
  what it cannot read — but that phase is already red as "without a summary".
- **The budget runs out between phases** → the next phase is not started; it is
  absent from `phases`, so "N phase(s) never ran" (#27) still reports it.
- **Caps that are not numbers** → exit 2 before anything starts.

## Out of Scope

- The Review phase's cap (#30). Billing outside the CLI's own `total_cost_usd`.

---

# Increment: review phase with one spec fix round (#30)

Tracks [#30](https://github.com/fernandodof/cal.diy-2/issues/30). Builds on #31
(merged in #40).

## Overview

After Implement, a fourth headless session runs `/code-review` against the base
and writes its findings as JSON as well as prose. If any **spec** finding says a
requirement is missing or wrong, the harness runs **one** fix session on exactly
those findings, then never reviews again. Standards findings are reported, never
fixed. The evidence carries every finding with its axis and severity, and whether
the fix round ran.

## Problem Statement

The criteria from #29 prove the tests named for each requirement pass; nothing
yet asks whether the diff does what the issue asked or follows the repo's
conventions. `/code-review` (user-level skill) answers both, on separate axes.

## Technical Design

### Review as headless phase 4 of `/implement-task`

`headless.md` gains a **Phase 4 — Review** section, so all headless rules stay in
one file and the gate-file contract (#27) carries over unchanged:

```
/implement-task --headless --phase 4 --base <b> <issue URL> --spec specs/<slug>
```

The phase runs `/code-review` with everything it would otherwise ask for given up
front — this repo has no `docs/agents/issue-tracker.md`, and the skill's fallback
is to stop and ask:

- fixed point: `origin/<base>`;
- spec: `<spec>/design.md` and the issue URL (`gh issue view` is allowed);
- standards: `CONTRIBUTING.md` plus the skill's smell baseline.

It then writes, besides `gates/4-review.md` (`Outcome:` line + the two prose
sections, committed), `.claude/headless-runs/review.json` (gitignored, like
`pr-body.md`):

```jsonc
{ "findings": [
  { "axis": "spec",      "kind": "missing",   "severity": "hard",      "summary": "…", "where": "file:line", "quote": "…spec line…" },
  { "axis": "standards", "kind": "smell",     "severity": "judgement", "summary": "…", "where": "…" }
] }
```

`kind` is the skill's own categories: spec `missing` | `creep` | `wrong`;
standards `violation` | `smell`. `severity` is its hard-vs-judgement split
(smells are always `judgement`).

### Fix round

- **Trigger:** at least one spec finding of kind `missing` or `wrong` — #30's
  "a requirement missing or wrong". Scope creep is reported, not fixed: undoing
  it is a judgement for the reviewer.
- **Session:** `/implement-task --headless --phase fix …`, a new `headless.md`
  section: read `review.json`, fix only those findings, add or update the tests
  and criteria they touch, commit, update `pr-body.md`. No new scope.
- **Exactly once.** No second review follows; the findings in the evidence are
  the ones the fix round was given, rendered under "Review (before the fix
  round)". The collector runs afterwards as always, so criteria and tests reflect
  the fixed code.

### Permissions and budget

- `/code-review` spawns two sub-agents, so the **review session alone** gets
  `Agent` added to its allowlist; every other session's list is unchanged.
  Sub-agents run under the same deny list.
- Caps: `HEADLESS_TASK_MAX_TURNS_REVIEW` (30, as #31 left for here) and
  `HEADLESS_TASK_MAX_TURNS_FIX` (40); both inside the one cost cap. They join
  `budget.turn_caps` as `4-review` and `fix`.

### Evidence (`implement-evidence/1`, additive)

- `phases` gains `4-review` and, when it ran, `fix` records — same shape.
- `review`: `{findings: [...], fix_round_applied: bool}`; `null` if the review
  did not run or left no readable `review.json`.

### Verdict

- Review ran (Implement completed) but `review == null` → red: "review: no findings
  were recorded".
- A `fix` phase that failed → red via the existing per-phase rule.
- Findings themselves do **not** turn the verdict red: every PR is a draft a human
  reads, and after the fix round the harness has no second opinion on whether
  they still hold. The block lists them first under the evidence, by axis.
- "phases: N phase(s) never ran" now counts against four, not three: the review
  is part of a complete run. `agent.status: completed` requires the review too.

### Files

| File | Change |
|---|---|
| `.claude/skills/implement-task/headless.md` | Phase 4 (review) and fix-round sections |
| `scripts/issue-to-pr.sh` | review session (+`Agent`), fix trigger and session, two caps |
| `scripts/implement-evidence.sh` | `review`, phase count 4, aggregate `agent` |
| `scripts/implement-verdict.sh` | the null-review rule, findings in the block, four-phase count |
| `docs/harness/implement-evidence-schema.md` | `review`, the new phases and caps |

Five non-test files.

## Edge Cases

- **Earlier phase stopped** → no review, no fix; unchanged behaviour.
- **Review session fails or hits its cap** → no fix round; red as a failed phase.
- **`review.json` unparseable or missing fields** → `review: null`, red.
- **Fix session makes no commit** → `fix_round_applied: true` still (it ran),
  and its phase record shows what it did; the collector judges the code.

## Out of Scope

- Re-reviewing after the fix; a second fix round; auto-fixing standards findings.

---

# Increment: handoff files outside `.claude/` (#51)

Tracks [#51](https://github.com/fernandodof/cal.diy-2/issues/51). Found by the
#33 smoke run on #11 (PR #42).

## Overview

Phase 3 writes `pr-body.md`, and Phase 4 writes `review.json`, for the harness
to read. Both currently go under `.claude/headless-runs/`, where a headless
session cannot write. They move to a gitignored `.agent-handoff/` at the
worktree root. The harness's own run logs stay in `.claude/headless-runs/`:
bash writes those, not the agent.

## Problem Statement

The smoke run's Phase 3 and Phase 4 sessions both had their `Write` denied as a
"sensitive file" (`permission_denials` in `.claude/headless-runs/issue-11/{3-implement,4-review}/result.json`).
So the PR opened without the agent's body, and the review was recorded as
missing, which made the verdict red. Two probes against a real `claude -p`
session (Haiku, `--permission-mode acceptEdits`, the same flags as
`headless-task.sh`) showed:

- A `Write` to `.claude/headless-runs/a.md` is denied. Adding an explicit
  `Write(.claude/headless-runs/**)` allow rule doesn't change that, so
  allowlisting cannot fix it.
- A `Write` to `.agent-handoff/b.md` (gitignored, directory not created in
  advance) and to `specs/c.md` succeeds. `Write` creates the directory itself,
  so the agent needs no `mkdir`.

The fake `claude` in `scripts/issue-to-pr.test.sh` writes with plain bash, so it
could never see this.

## Technical Design

One path, `.agent-handoff/`, relative to the worktree root, for both files:

| Today | After |
|---|---|
| `.claude/headless-runs/pr-body.md` | `.agent-handoff/pr-body.md` |
| `.claude/headless-runs/review.json` | `.agent-handoff/review.json` |

`.gitignore` gains `.agent-handoff/`. The worktree is cut from the base, so the
entry has to be on the base for an agent's `git add` to skip the files.

### Files

| File | Change |
|---|---|
| `.gitignore` | add `.agent-handoff/` |
| `.claude/skills/implement-task/headless.md` | the four mentions of the path (Phase 3, Phase 4, fix round) |
| `scripts/issue-to-pr.sh` | `review.json` (fix trigger, line 284) and `pr-body.md` (PR body, line 328) |
| `scripts/implement-evidence.sh` | `REVIEW_FILE` (line 210) |
| `docs/harness/implement-evidence-schema.md` | where `review` comes from (line 156) |
| `scripts/issue-to-pr.test.sh` | the fake `claude` writes both files to the new path |

Five non-test files; about 15 changed lines.

## Edge Cases

- **A worktree left over from an earlier run** (e.g. `issue-11`) still has files
  in the old path. The harness reads only the new path, so they are ignored.
  Re-runs are #32's job; this increment adds no migration.
- **The base branch has no `.agent-handoff/` entry in `.gitignore`** (a base
  other than `main` cut before this merges). The agent's `git add` could then
  commit the files. The rules already say not to commit them; nothing more is
  added here.

## Out of Scope

- The PR-body fallback text not pointing at the gate file (#45).
- Moving the harness's run logs out of `.claude/headless-runs/`: bash writes
  them, so they are not affected.
- A test against a real session: the probes above, plus re-running #11 after
  merge, are the check. The fake-`PATH` tests can only show that the harness and
  the rules use the same path.

---

# Increment: the agent runs biome before committing (#44)

Tracks [#44](https://github.com/fernandodof/cal.diy-2/issues/44). Found by both
#33 smoke runs on #11 (PRs #42 and #53). In the second run, biome was the only
reason the verdict was red.

## Overview

Phase 3's per-slice Verify step adds `yarn biome check --write` on the files the
slice changed. That is the same `biome check` the harness's evidence runs, with
the safe fixes applied. The fix round verifies the same way, so it inherits the
step.

## Problem Statement

In both runs, the agent's two new test files had `import { describe, it, expect }`,
and the evidence's `yarn biome check` failed them with
`assist/source/organizeImports`. The agent never ran biome, because
`phases/3-implement.md`'s Verify section lists only `yarn test` and the `@calcom/web`
type-check. The pre-commit hook didn't catch it either: `lint-staged.config.mjs`
runs `biome lint`, and import sorting is a biome *assist*, which `lint` does not
run. A probe on a scratch `packages/lib` test file with those imports showed:

- `yarn biome lint` exits 0;
- `yarn biome check --no-errors-on-unmatched` exits 1;
- `yarn biome check --write` exits 0 and rewrites the import to
  `{ describe, expect, it }`, after which `check` exits 0.

`Bash(yarn biome:*)` is already on the session allowlist (`scripts/issue-to-pr.sh:206`),
so no permission change is needed.

## Technical Design

- `phases/3-implement.md`, Verify: add the biome command, and say why the
  pre-commit hook is not enough. "Both must pass" becomes "All three". Because the
  phase file is shared, interactive runs get the step too, and the CLAUDE.md
  convention that `yarn lint`/`yarn format` run biome holds for them as well.
- `headless.md`, fix round: "Commit as in Phase 3" becomes "Verify and commit as
  in Phase 3", so the fix round's edits are checked the same way.

### Files

| File | Change |
|---|---|
| `.claude/skills/implement-task/phases/3-implement.md` | biome in the Verify block, and why the hook is not enough |
| `.claude/skills/implement-task/headless.md` | the fix round verifies as Phase 3 does |
| `scripts/issue-to-pr.test.sh` | the rules name `yarn biome check --write`, and the allowlist covers it |

Two non-test files; about 15 changed lines.

## Edge Cases

- **A slice that changes no file biome reads** (shell, markdown): biome with
  `--no-errors-on-unmatched` checks nothing and exits 0. The evidence still
  records that as not run (#46, closed as not planned).
- **`--write` changes a file after the tests ran**: only formatting and import
  order change, so behaviour does not. The harness re-runs the tests itself in
  any case.

## Out of Scope

- Changing the pre-commit hook to `biome check`: that is an upstream Cal.com
  file, and upstream conventions beat ours.
- Type-check coverage (#43).

---

# Increment: type-check the files the change touched (#43)

Tracks [#43](https://github.com/fernandodof/cal.diy-2/issues/43), including the
evidence tidy-ups folded in from #45. Found by all three #33 smoke runs on #11.

## Overview

Besides the `@calcom/web` type-check, the collector runs `tsc --noEmit` once
for each TypeScript project a changed `.ts`/`.tsx` file belongs to. It judges
only the errors reported in the changed files. The agent gets an allowlisted way
to run the same command, and the Verify step tells it to. The tidy-ups make the
evidence block render to the cent, drop temp paths, keep a run directory to the
current run's files, and point the no-draft fallback at the gate file.

## Problem Statement

`yarn turbo run type-check --filter=@calcom/web` compiles only what web imports
(`scripts/implement-evidence.sh:225`). New `packages/lib/*.test.ts` files are
imported by nothing, so all three runs reported type-check **pass** for test
files that were never type-checked. The agent's own
`yarn tsc --noEmit -p tsconfig.json` was denied every time.

Probes on `main` (`8ed5a0abe2`):

- `yarn tsc --noEmit -p packages/lib/tsconfig.json` takes 5 s and exits 2 with
  **69 existing errors**: 37 in `packages/lib` (27 of them in test files), 31 in
  `packages/dayjs` (pulled in through imports), and 1 in `packages/emails`.
  `packages/features` takes 12 s with 89 errors; `trpc` takes 10 s and
  `app-store` 9 s, with 0 errors each. **A package's exit code therefore can't
  be the verdict**: it is red on `main` already.
- The project includes its test files (`"include": ["."]`). A scratch
  `packages/lib/zzProbe.test.ts` with `const x: number = "a"` is reported as
  `packages/lib/zzProbe.test.ts(1,7): error TS2322: …`, a path relative to the
  repo root when `tsc` runs from there. Matching on changed paths is therefore
  exact.
- Every `packages/*` and `apps/*` directory either has a `tsconfig.json` or
  holds sub-packages that do (`embeds`, `platform`, `config`, …). There is no
  root `tsconfig.json`.

## Technical Design

### The check

For each changed `.ts`/`.tsx` file (added or modified, as `CHANGED_FILES`
already holds), find the nearest ancestor directory with a `tsconfig.json`.
Then:

- **`apps/web`**: skip it. The existing `@calcom/web` check covers it.
- **Any other project**: run it once, from the worktree root:
  `yarn tsc --noEmit -p <dir>/tsconfig.json`. Keep the error lines whose path is
  one of the changed files.
- **No `tsconfig.json` up to the repo root**: the file is not covered.

Each project becomes one check, named `type-check: <dir>`, with `source:
"always"`:

| Field | Value |
|---|---|
| `command` | the `tsc` command above |
| `exit_code` | `0` if the changed files have no errors, `1` if they have any, `null` if `tsc` printed no `error TS` line yet exited non-zero (it crashed, or never ran) |
| `log_tail` | the error lines for the changed files; otherwise one line: `no errors in N changed file(s); M error(s) elsewhere in the project` |
| `scope` *(new, additive)* | `"changed files"` |

Files with no project at all become one check, `type-check: not covered`, with
`exit_code: null` and the file list. That makes it red under the existing rule
that a check that did not run is red. That's honest, and so far rare: only
scripts outside every package.

The verdict needs no new rule. An `exit_code` of 1 is already red as "check:
type-check: packages/lib exited 1", and `null` as not run.

### The agent

- The allowlist gains `Bash(yarn tsc --noEmit -p:*)`.
- `phases/3-implement.md` Verify adds that command for each project the slice
  touched. It also corrects the paragraph that says `@calcom/web` covers changes
  in `packages/lib`: it covers only what web imports. The agent checks only that
  its own files have no errors; the existing errors elsewhere are not its job.

### Tidy-ups (from #45)

- Costs render to the cent in the evidence block (`$0.27`, not `$0.27312559999999997`).
- Check commands in the evidence show no temp paths. The `--outputFile.json=…`
  argument is dropped from the displayed command; the command that runs is
  unchanged.
- At the start of a run, an existing run directory is moved aside as
  `issue-N-<UTC timestamp>`, so the new directory holds only that run's files.
  Today `phases.jsonl` is emptied, but stale `result.json` and `task.txt` files
  from older `headless-task.sh` runs survive. The old directory is moved rather
  than deleted because the new run may still be refused, for example at "branch
  already exists", and its logs are the only record of the earlier run.
- `Closes #N` appears once, even when the agent's draft has its own (seen in
  run 2).
- The no-draft fallback names the gate file the agent's draft may be in, when
  there is one.

### Files

| File | Change |
|---|---|
| `scripts/implement-evidence.sh` | per-project `tsc`, filtered to changed files; `scope`; no temp path in the displayed command |
| `scripts/issue-to-pr.sh` | allowlist; empty the run dir; fallback text |
| `scripts/implement-verdict.sh` | costs to the cent |
| `.claude/skills/implement-task/phases/3-implement.md` | the `tsc` step; the corrected coverage paragraph |
| `docs/harness/implement-evidence-schema.md` | the per-project checks, `scope` |
| `scripts/issue-to-pr.test.sh`, `scripts/implement-verdict.test.sh` | tests |

Five non-test files.

## Edge Cases

- **A changed file that already had errors on the base**: its errors count, so
  it is red. The change touched it, so it is the change's to fix or to explain.
  Telling old errors from new would mean a second `tsc` at the merge base; not
  done in this increment.
- **A deleted file**: not in `CHANGED_FILES` (`--diff-filter=d`), so not checked.
- **`.mts`/`.cts`/`.js`**: not type-checked; only `.ts`/`.tsx` files are mapped
  (a `.d.ts` ends in `.ts`, so it is).
- **Two changed files in one project**: one `tsc` run, both filtered.
- **`tsc` itself is slow for a large project**: about 12 s worst case measured
  (`features`). It runs once per project, not per file.

## Out of Scope

- Fixing the 69 existing errors in `packages/lib` and `packages/dayjs`, or the
  89 in `packages/features`.
- Comparing against the base to tell old errors from new.
- `apps/api` needs nothing special: it has no tsconfig at its root, and its
  sub-apps have their own.

---

# Increment: the agent reads only what the trust gate approved (#48)

Tracks [#48](https://github.com/fernandodof/cal.diy-2/issues/48).

## Overview

The agent no longer reads GitHub itself. The issue's title and body, as the
harness fetched them and the trust gate approved them, go into the prompts of
the phases that need the issue (Research and Review). `gh` leaves the
allowlist and is denied outright. The trust gate also refuses an issue whose
last editor is not the owner, unless `--trust` is given.

## Problem Statement

The trust gate (#25) checks the issue's author. The agent, however, had
`Bash(gh issue view:*)`, and `headless.md` told Phase 4 to read the issue that
way. That command also takes `--comments`, any issue number, and
`-R <other repo>`. The repo is public, so anyone's comment, or any other issue,
could reach a session that edits and commits code.

Checked during research:

- **Edits:** the only collaborator is the owner
  (`gh api repos/fernandodof/cal.diy-2/collaborators`), so today nobody else can
  edit the owner's issue body or title. GraphQL exposes the last `editor` (`null`
  on #11), so the gate can check it cheaply in case that changes.
- **Probe** (real `claude -p`, Haiku): with `Bash(gh:*)` on the deny list,
  `gh issue view 11 --comments` is denied while `ls` runs.

## Technical Design

- **Allowlist:** drop `Bash(gh issue view:*)`. **Deny list:** `Bash(gh pr:*)`
  becomes `Bash(gh:*)`, which covers `gh issue`, `gh api` and `gh pr`. The
  harness keeps using `gh` itself.
- **Prompts:** Phase 1 already carries `# Issue #N: <title>` and the body from
  `issue.json`. Phase 4 now carries it too. Phases 2, 3 and fix read only the
  spec and `review.json`, so they don't change.
- **`headless.md`:** Phase 1 reads the issue from the prompt, as now. Phase 4's
  spec is `<spec>/design.md` plus the issue text in the prompt. It doesn't read
  GitHub, and it doesn't use `gh`.
- **Trust gate:** after the author check, fetch the last editor with
  `gh api graphql` (`repository.issue(number).editor.login`). If it is set and
  isn't the owner, refuse with exit 3 unless `--trust`, as for a stranger's
  issue. If the query fails, refuse as well: a gate that can't see is closed.

### Files

| File | Change |
|---|---|
| `scripts/issue-to-pr.sh` | allow and deny lists; issue text in Phase 4's prompt; editor check |
| `.claude/skills/implement-task/headless.md` | Phase 4 reads the issue from the prompt, never `gh` |
| `scripts/issue-to-pr.test.sh` | tests |

Two non-test files.

## Edge Cases

- **An owner's issue edited by a collaborator** → refused unless `--trust`.
- **The editor query fails** (network, rate limit) → refused with exit 2, nothing
  created.
- **`/code-review`'s sub-agents** run under the same deny list, so they can't
  call `gh` either.

## Out of Scope

- Comments as a source of requirements. If one matters, the owner moves it into
  the body.
- Linked issues and PRs named in the body: the agent sees their numbers, not
  their content.
