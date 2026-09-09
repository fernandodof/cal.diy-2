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

## Verify

Both must pass before the PR. Scope them — the full suite is slow here.

```bash
# Tests for what you touched (yarn test is `TZ=UTC vitest run`)
yarn test <path/to/file.test.ts>

# Type-check the affected workspace
yarn turbo run type-check --filter=@calcom/features
```

Workspace names are the `name` field of the package's `package.json` —
`@calcom/features`, `@calcom/lib`, `@calcom/trpc`, `@calcom/web`. `yarn
type-check` with no filter runs the whole monorepo and is rarely what you want.

If either fails, fix it. Never open a PR on red, and never describe a failing
check as passing — report the actual output.

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
- `yarn turbo run type-check --filter=@calcom/<package>` — <result>
```

Report check results honestly. If something was skipped or is failing, say which
and why — a PR body that claims green on red is worse than no PR body.

### Create it

The base branch is **asked, never assumed** — `origin` here is a personal fork of
cal.com, so this fork's `main` and upstream are both plausible targets and
picking wrong sends the change to the wrong place.

```bash
git push -u origin <branch>
gh pr create --base <the branch the user named> --title "<conventional commit title>" --body "$(cat <<'BODY'
...body from the template...
BODY
)"
```

PR descriptions end with the generation footer from the session's attribution
instructions.

Return the PR URL to the user as the final output.
