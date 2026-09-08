---
name: implement-task
description: Take a task description all the way to an open pull request in this Cal.com fork — ground it in the codebase, slice it into tracer bullets, implement, verify, and open the PR. Use when the user describes a feature or bug to build, says "implement this", "build this and open a PR", or hands over a ticket, issue, or spec to ship.
---

# Implement Task

Task description in, reviewed PR out. Work through the phases in order. Two
checkpoints are mandatory: **after the slice plan** and **before opening the PR**.
Everything between them runs without stopping.

## Phase 1 — Ground the task

Never plan from the task description alone. Establish, in this order:

1. **Read `CLAUDE.md`** for the area being touched. The fork records product
   decisions the schema cannot express. If the task contradicts one — e.g. asking
   to auto-cancel or auto-reschedule a booking, which decision #2 forbids — **stop
   and say so before writing code**. Quote the decision and ask whether to proceed
   anyway or change the approach.
2. **Locate the code** using the checklist in
   [GROUNDING.md](GROUNDING.md). Name the concrete files you expect to touch.
3. **Find the nearest existing test** for that area and read it. It defines the
   conventions your new tests must match — don't invent a testing style.

Restate the task in one or two sentences, listing the files you'll touch. If the
task is ambiguous in a way that changes what gets built, ask now.

## Phase 2 — Slice into tracer bullets

Break the work into **vertical slices**. A tracer bullet cuts through every layer
end-to-end — schema, service, tRPC handler, UI, tests — narrow but complete.

<slice-rules>
- Each slice is demoable or verifiable on its own.
- No horizontal slices: "add the DB column" is not a slice; "one booking shows
  the warning, end to end" is.
- Prefer many thin slices over few thick ones.
- Order them so slice 1 is the thinnest thing that proves the path works.
</slice-rules>

**CHECKPOINT — present the plan and wait for approval.** Show a numbered list:
title, what it proves end-to-end, files touched, and what verifies it. Ask
whether granularity and ordering are right. Do not write code until the user
approves.

## Phase 3 — Implement

Branch off `main` first: `git checkout -b feat/<short-kebab-description>`
(`fix/…` for bugfixes).

Then, **for each slice in order**:

1. Write the test first where there's a clean seam — a pure function, a service
   method, a resolver. Watch it fail for the right reason.
2. Implement the thinnest thing that makes it pass.
3. Verify the slice (Phase 4 commands, scoped to what changed).
4. **Commit the slice** as one conventional commit:
   `feat(travel-schedule): warn host about bookings outside working hours`
   Scope matches the feature area. See [PR.md](PR.md) for the commit trailers.

One commit per slice — the PR should read as the slice progression.

Match the surrounding code: its naming, its comment density, its idioms. This is
a Cal.com fork; upstream conventions win over personal preference.

## Phase 4 — Verify

Both must pass before the PR. Scope them — the full suite is slow in this monorepo.

```bash
# Tests for what you touched
yarn test <path/to/file.test.ts>

# Type-check the affected workspace
yarn turbo run type-check --filter=@calcom/<package>
```

If either fails, fix it. Never open a PR on red, and never describe a failing
check as passing — report the actual output.

## Phase 5 — Open the PR

**CHECKPOINT — before pushing.** Show the diff summary (`git diff main --stat`),
the drafted PR title and body, and **ask which base branch to target**. This fork's
`origin` is a personal fork of cal.com; never assume upstream. Wait for the answer.

Then push and create the PR. Body template, trailers, and the `gh` invocation are
in [PR.md](PR.md).

Report the PR URL when done.
