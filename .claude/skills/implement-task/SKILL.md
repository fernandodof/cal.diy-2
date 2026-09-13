---
name: implement-task
description: Take a task description all the way to an open pull request in this Cal.com fork through three handoff phases — Research, Plan, Implement. Use when the user describes a feature or bug to build, says "implement this", "build this and open a PR", or hands over a ticket, issue, or spec to ship.
---

# Implement Task

Task description in, open pull request out, through three phases. Each phase
writes a file; the next phase reads that file and nothing else from the phase
before it. If the handoff file cannot be written, the next phase does not start.

The phase artifacts live in `specs/<feature-slug>/`, the structure this repo
already uses (see `SPEC-WORKFLOW.md` and `specs/README.md`). They are committed
with the work, so a later session — or a reviewer — can pick the task up cold.

| Phase | Reads | Writes | Gate |
|---|---|---|---|
| 1 Research | the task, the codebase | `specs/<slug>/design.md` | user confirms the findings |
| 2 Plan | `design.md` | `specs/<slug>/implementation.md` | user approves the slices and names the base branch |
| 3 Implement | `implementation.md` | code, commits, the PR | user confirms the diff and PR body |

Run `/implement-task` with no phase named and it starts at Phase 1. Resuming
work? Read `specs/<slug>/implementation.md` first and re-enter at the phase its
`## Status` line implies.

## Phase 1 — Research

Never plan from the task description alone. Follow
[phases/1-research.md](phases/1-research.md) to locate the real code, then write
`specs/<slug>/design.md` from `specs/_templates/design.md`. The phase file
creates the spec folder — it checks for an existing one first, so do not copy
the template from here.

**GATE.** Show the design's Overview, the file list, and any open question. The
user confirms or corrects before planning. Do not slice yet.

## Phase 2 — Plan

Read `specs/<slug>/design.md` — the design is now the source of truth, not the
original request. Follow [phases/2-plan.md](phases/2-plan.md) to break it into
tracer bullets and write them into `specs/<slug>/implementation.md`.

**GATE.** Present the numbered slices. Ask whether the granularity and ordering
are right, **and which branch this will merge into** — the working branch is cut
from that base, so it is needed before any code lands, not at PR time. Do not
write code until the user approves.

## Phase 3 — Implement

Read `specs/<slug>/implementation.md` and work its slices in order. Follow
[phases/3-implement.md](phases/3-implement.md) for the per-slice loop,
verification commands, and the pull request.

**GATE.** Before pushing, show `git diff <base> --stat` against the base chosen in
Phase 2, plus the drafted PR body. Confirm that base is still the intended target
— it is recorded in `implementation.md` — rather than defaulting to `main`.

Report the PR URL when done.

## Rules that hold across all three phases

- **Anything a phase asserts about the codebase must be verified in it.** Cite
  the file you read. A path you did not open does not go in a handoff file.
- **Report check results honestly.** Never describe a failing or skipped check
  as passing.
- **Match the surrounding code** — its naming, comment density, and idioms.
  This is a Cal.com fork; upstream conventions beat personal preference.
