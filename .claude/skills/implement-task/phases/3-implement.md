# Phase 3 — Implement

**Input:** `specs/<slug>/implementation.md` from Phase 2.
**Output:** commits on a branch, and an open pull request.

Work the slices under `## Next Steps` in order. Set `## Status: in-progress`
before the first one.

## The per-slice loop

For each slice:

1. **Test first where there is a clean seam** — a pure function, a service
   method, a resolver. Watch it fail for the right reason. Match the conventions
   of the test you read in Phase 1; do not invent a testing style.
2. **Implement the thinnest thing that passes.**
3. **Verify** with the commands below, scoped to what changed.
4. **Commit the slice** as one conventional commit scoped to the feature area:

   ```
   feat(bookings): require cancellation reason when the event type demands it
   fix(emails): customReplyToEmail no longer dropped when hideOrganizerEmail is true
   ```

   End every commit message with the attribution trailers this session is
   configured with — read the session's current attribution instructions rather
   than copying a block from here, since they change per session.
5. **Update `implementation.md`** — move the slice from `## Next Steps` to
   `## Completed`, and add a line under `## Session Notes` saying what was done
   and what is next. Include this in the slice's commit.

One commit per slice, so the PR reads as the slice progression. A slice that
turns out to be wrong updates the plan file first, then the code.

**When a slice cannot be completed** — a constraint that blocks it, a failing
check you cannot fix, something the design does not answer — set
`## Status: blocked`, write what blocked it and what you tried under `## Blocked`,
commit that, and stop. Do not start the next slice, and do not work around a
blocker the design did not anticipate. Surface it: the resume path reads
`## Status`, so a blocked task that is left as `in-progress` looks resumable and
is not.

## Verify

Both must pass before the PR. Scope them — the full suite is slow here.

```bash
# Tests for what you touched (yarn test is `TZ=UTC vitest run`)
yarn test <path/to/file.test.ts>

# Type-check
yarn turbo run type-check --filter=@calcom/web
```

**Most packages have no `type-check` task of their own.** Of the workspace names
you are likely to reach for, only `@calcom/web` has one (`tsc --pretty --noEmit`);
`@calcom/features`, `@calcom/lib` and `@calcom/trpc` do not. `@calcom/web`
compiles what it imports, so it is the check that actually covers a change in
those packages.

This matters because **turbo exits 0 for a task that does not exist.** A filter
naming a package without a `type-check` script prints `Tasks: N successful` and
returns 0 without type-checking anything. Before trusting a different `--filter`,
confirm the task is real:

```bash
yarn turbo run type-check --filter=<pkg> --dry=json   # command must not be "<NONEXISTENT>"
```

`yarn type-check` with no filter runs the whole monorepo and is rarely what you
want.

If either fails, fix it. Never open a PR on red, and never describe a failing
check as passing — report the actual output. A check that exited 0 without
running is not a pass: say it did not run.

## Open the pull request

Set `## Status: complete` in `implementation.md` and commit that before pushing.

### PR body template

```markdown
## What changed

<One paragraph: the behavior that is different now, from the user's point of view.>

## Tracer bullets

1. <Slice title> — <what it proves end-to-end>
2. <Slice title> — <what it proves end-to-end>

## Design

Spec: `specs/<feature-slug>/design.md` — <one line on the approach it settled on>
<Cite an ADR from decisions.md if one shaped this change.>

## How to verify

<Numbered steps a reviewer can actually follow in the running app or the tests.>

Checks run on this branch:

- `yarn test <path>` — <result>
- `yarn turbo run type-check --filter=@calcom/web` — <result>
```

Report check results honestly. If something was skipped or is failing, say which
and why — a PR body that claims green on red is worse than no PR body.

### Create it

The base branch is the one the user named at the Phase 2 gate, which the working
branch was cut from — it is recorded in `implementation.md` under
`## Session Notes`. Never assume `main`: this repo is a personal fork of cal.com
and a long-lived feature branch is a plausible target, so confirm the recorded
base still matches the user's intent before pushing rather than defaulting.

```bash
git push -u origin <branch>
gh pr create --base <the recorded base> --title "<conventional commit title>" --body "$(cat <<'BODY'
...body from the template...
BODY
)"
```

PR descriptions end with the generation footer from the session's attribution
instructions.

Return the PR URL to the user as the final output.
