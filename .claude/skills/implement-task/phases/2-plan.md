# Phase 2 — Plan

**Input:** `specs/<slug>/design.md` from Phase 1.
**Output:** `specs/<slug>/implementation.md`, the slice list Phase 3 executes.

Read the design first. From here on it is the source of truth — if the original
request and the design disagree, the design wins, because the user confirmed it.
Something genuinely missing from the design means going back to Phase 1, not
patching it in here.

## Slice into tracer bullets

A tracer bullet cuts through every layer end-to-end — schema, service, tRPC
handler, UI, test — narrow but complete.

<slice-rules>
- Each slice is demoable or verifiable on its own.
- No horizontal slices: "add the DB column" is not a slice; "one event type
  saves and reloads the new setting, end to end" is.
- Prefer many thin slices over few thick ones.
- Order them so slice 1 is the thinnest thing that proves the path works.
- Every slice names the files it touches, taken from the design's file list.
  A file that appears in no slice but is in the design is a gap — resolve it.
</slice-rules>

Check the total against the review-size rule in `specs/README.md`: 5-7 files
excluding tests, 500 lines. Over it, say so now and propose the split into more
than one PR rather than discovering it at push time.

## Write implementation.md

`specs/_templates/implementation.md` gives the skeleton — `## Status`,
`## Completed`, `## In Progress`, `## Blocked`, `## Next Steps`,
`## Session Notes`. Keep those headings; Phase 3 updates them as it goes and a
resumed session reads `## Status` to know where it stopped.

Set `## Status: planned` and put the slices under `## Next Steps`, numbered, each
with what it proves end-to-end, its files, and what verifies it:

```markdown
## Next Steps

1. **Setting persists on the event type** — proves schema → tRPC → form round-trip
   - `packages/prisma/schema.prisma`, `apps/web/modules/event-types/components/tabs/advanced/EventAdvancedTab.tsx`
   - Verified by: `yarn test <the nearest test file>`, plus loading the tab
2. **Validation enforces it on cancel** — proves the setting reaches the server path
   - `packages/features/bookings/lib/handleCancelBooking.ts`
   - Verified by: `yarn test packages/features/bookings/lib/handleCancelBooking/test/handleCancelBooking.test.ts`
```

If choosing between approaches was part of planning, record it as an ADR in
`specs/<slug>/decisions.md` — Context, Options Considered, Decision,
Consequences, per `specs/_templates/decisions.md`. Deferred ideas go in
`future-work.md` rather than swelling the slice list.

## Gate

Present the numbered slices and ask whether granularity and ordering are right.
Do not write code until the user approves. On approval, commit the spec so the
plan is in the branch's history before any implementation lands:

```bash
git checkout -b feat/<feature-slug>   # fix/… for bugfixes
git add specs/<feature-slug>
git commit -m "docs(<area>): design and plan for <feature>"
```
