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
