# Outside Working Hours Warning Implementation

## Status: in-progress

## Completed

1. **The predicate exists and is correct in isolation** — `isOutsideRecurringHours`
   and `getRecurringAvailability` in
   `packages/features/bookings/lib/isOutsideRecurringHours.ts`, with 11 tests in
   the sibling `.test.ts`. Covers recurring-only rows, override-created times,
   boundary-spanning bookings, hosts with no recurring rows, the 11:59PM
   allowance, and two explicit non-UTC timezone cases.
   - `yarn test packages/features/bookings/lib/isOutsideRecurringHours.test.ts` — 11 passed
   - `yarn turbo run type-check --filter=@calcom/web` — passed

2. **A host's upcoming list flags an override booking, end to end** —
   `flagBookingsOutsideWorkingHours` annotates the payload in `getHandler`, and
   `BookingItemBadges` renders an orange badge with a tooltip.
   - `packages/features/bookings/lib/flagBookingsOutsideWorkingHours.ts` (new)
   - `packages/trpc/server/routers/viewer/bookings/get.handler.ts`
   - `apps/web/components/booking/BookingListItem.tsx`
   - `packages/i18n/locales/en/common.json`
   - `yarn test packages/trpc/server/routers/viewer/bookings/get.handler.test.ts` — 9 passed
   - `yarn turbo run type-check --filter=@calcom/web` — passed
   - `useBookingListColumns.tsx` needed no change: `BookingItemProps` derives from
     `RouterOutputs`, so the field reaches the row once the handler returns it.

3. **A slot carries its override provenance to the client** — slots are flagged
   after `getSlots` and the field rides the existing `passThroughProps` spread.
   - `packages/trpc/server/routers/viewer/slots/util.ts`
   - `yarn test packages/trpc/server/routers/viewer/slots/util.test.ts` — 1 passed
   - `yarn turbo run type-check --filter=@calcom/web` — passed
   - `returnDateOverrides` was **not** flipped: the raw availability rows are
     already loaded regardless of it, and `findForSlots` already selects
     `schedule.availability`. See the revised ADR-001.

## In Progress

## Blocked

## Next Steps

4. **The booker sees the notice on the confirm step** — proves the full
   user-visible feature.
   - `apps/web/modules/bookings/components/BookEventForm/BookEventForm.tsx`
   - `packages/i18n/locales/en/common.json`
   - Verified by: selecting an override-created slot in the booker and reaching
     the confirm step
   - New branch in the existing alert ternary (ends line 175), `severity="info"`
     matching lines 140 and 156. Confirm button stays enabled. The
     `isTimeslotUnavailable` branch takes precedence — blocking outranks
     advisory.

## Session Notes

- **Base branch: `main`.** Working branch `feat/outside-working-hours-warning`
  is cut from `origin/main`. Phase 3 uses this as `gh pr create --base main`.
- Design decisions were settled in a prior grilling session; `design.md` is the
  source of truth, not the original request. Two premises from that session were
  corrected during research and must not be reintroduced:
  - a booker **can** book outside normal hours via date overrides — such slots go
    through the ordinary gate, since `dateRanges` merges overrides in;
  - `dateOverrides` was **not** reaching the booker (`slots/util.ts:816`), which
    is what slice 3 fixes. See ADR-001 in `decisions.md`.
- File count is seven excluding tests, at the top of the `specs/README.md:77-81`
  limit. If Phase 3 pushes past it, slices 3-4 (the booker surface) split into a
  second PR; slices 1-2 stand alone as a shippable unit.
- Slice 1 done. The predicate mirrors `processWorkingHours`
  (`date-ranges.ts:60-83`) on the three things that are easy to get wrong: the
  weekday is taken in the schedule's timezone, times are read as a UTC wall clock
  via `getUTCHours()`/`getUTCMinutes()`, and a 23:59 end extends to midnight.
  Next: slice 2, the bookings-list surface.
- Slice 2 done. Two things worth carrying forward: the flag has to be set on both
  branches of the upcoming check, or it does not survive into `RouterOutputs` and
  the row cannot read it; and the schedule lookup is wrapped in a `catch` so a
  failed lookup degrades to no badge rather than taking the bookings list down.
  Next: slice 3, plumbing override provenance through the slots endpoint.
- Slice 3 done, and it corrected a premise in the plan. `returnDateOverrides:
  false` is a deliberate CPU guard (`getUserAvailability.ts:439-441`: getSchedule
  calls this per team-event user without using the values), so flipping it would
  have reintroduced the cost it prevents. Not needed: the raw rows load at
  `getUserAvailability.ts:415` regardless, and `findForSlots` already selects
  `schedule.availability`. ADR-001 updated. Next: slice 4, the booker Alert.
</content>
