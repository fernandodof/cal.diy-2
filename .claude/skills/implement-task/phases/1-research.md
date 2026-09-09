# Phase 1 — Research

**Goal:** produce `specs/<feature-slug>/design.md` that names the actual files
the task touches. Output of this phase is the only input to Phase 2.

Cal.com is a large yarn/turbo monorepo. Work down this list until you can name
concrete files, then stop — this phase is wayfinding, not implementation.

## 1. Check whether a spec already exists

```bash
ls specs/
```

If a folder for this feature is already there, read its `design.md`,
`implementation.md`, and `decisions.md` before anything else. You are continuing
work, not starting it — extend the existing spec instead of writing a new one.
`specs/cancellation-reason-requirement/` is a worked example of a completed spec
if you need to see the shape.

Otherwise create the folder from the repo's template:

```bash
cp -r specs/_templates specs/<feature-slug>
```

## 2. Follow the user-visible surface inward

Start from what the user sees and walk toward the data.

| Layer | Where to look |
|---|---|
| Pages / routes | `apps/web/app/`, `apps/web/modules/` |
| Feature UI + logic | `packages/features/<area>/` |
| Shared components | `packages/ui/`, `packages/features/components/` |
| tRPC handlers | `packages/trpc/server/routers/viewer/<area>/` |
| Business logic | `packages/lib/`, `packages/features/<area>/lib/` |
| Schema | `packages/prisma/schema.prisma` |

`packages/features/` and `packages/trpc/server/routers/viewer/` share area names
(`availability`, `bookings`, `calendars`, …) — though not identically:
`eventtypes` in features is `eventTypes` in the tRPC router. Finding the area in
one narrows the search in the other; confirm the spelling with `ls` rather than
assuming.

## 3. Grep for the domain noun

Search the term the user used, not the term you would pick:

```bash
grep -rn "<DomainNoun>" packages/ apps/web/ --include=*.ts --include=*.tsx -l | head -20
```

Prisma model and enum names are the highest-signal search terms — they appear in
`packages/prisma/schema.prisma`, the queries, the tRPC handlers, and the
generated types at once.

## 4. Read the nearest existing test

```bash
find packages/features/<area> -name "*.test.ts" | head
```

Open one before writing any. It shows how this area builds fixtures and mocks
Prisma. `packages/features/bookings/lib/` has several if the area you are
touching has none.

Note that `yarn test` runs `TZ=UTC vitest run` (see `package.json`), so tests
execute under UTC regardless of your machine. Anything timezone-sensitive must
set its zone explicitly rather than lean on the ambient one.

## 5. Note the constraints you actually found

Only record constraints you read in a file during this phase. Real sources:

- an existing `specs/<other-feature>/decisions.md` whose ADR bears on this work
- `specs/<slug>/CLAUDE.md` if this feature already has one
- `SPEC-WORKFLOW.md` and `specs/README.md` — notably the review-size rule below
- the schema, a validator, or a handler that already constrains the behavior

If the task contradicts a constraint you found, **stop and surface it** before
writing the design. Quote the file and line, and ask whether to proceed anyway
or change the approach. Do not invent a constraint that no file states.

`specs/README.md` sets a hard rule worth carrying into Phase 2: every PR must be
reviewable in under 10 minutes — max 5-7 files changed excluding tests, max 500
lines. If the task is bigger than that, it is more than one PR, and the design
should say where the split falls.

## Write the design

Fill in `specs/<slug>/design.md` against `specs/_templates/design.md`. Its
sections — Overview, Problem Statement, User Stories, Technical Design
(Database / API / UI), Edge Cases, Out of Scope — are the template's; keep them.

Two additions make the file a usable handoff:

- Under Technical Design, list each file you expect to touch with a real path,
  the way `specs/cancellation-reason-requirement/design.md` does.
- Under Out of Scope, name any constraint from step 5 that shaped the design.

## Gate

Show the user the Overview, the file list, and any open question. Wait for
confirmation. Phase 2 reads `design.md`, so a wrong design is a wrong plan.
