# Outside Working Hours Warning Implementation

## Status: complete

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

3a. **Schedule resolution corrected after running the app** — the slots flag read
   `eventType.schedule` directly, which is null whenever an event type inherits
   the user's default schedule, so the booker flag never fired. Resolved through
   the full precedence chain instead.
   - `packages/features/bookings/lib/getScheduleForWorkingHours.ts` (new)
   - `packages/trpc/server/routers/viewer/slots/util.ts`
   - `yarn test packages/features/bookings/lib/getScheduleForWorkingHours.test.ts` — 5 passed
   - Verified against the running app: Sat 19 Sep returned 4 slots, **all 4
     flagged**; Fri 18 and Mon 21 returned 16 slots each, **0 flagged**.
   - See ADR-002 in `decisions.md`.

4. **The booker sees the notice on the confirm step** — a new branch in the
   existing alert ternary, `severity="info"`, confirm button left enabled and
   `isTimeslotUnavailable` keeping precedence over it.
   - `packages/features/bookings/Booker/utils/isTimeslotOutsideWorkingHours.ts` (new)
   - `apps/web/modules/bookings/components/Booker.tsx`
   - `apps/web/modules/bookings/components/BookEventForm/BookEventForm.tsx`
   - `packages/i18n/locales/en/common.json`
   - `yarn test packages/features/bookings/Booker/utils/isTimeslotOutsideWorkingHours.test.ts` — 6 passed
   - `yarn test apps/web/modules/bookings/components/Booker.test.tsx` — 4 passed
   - `yarn turbo run type-check --filter=@calcom/web` — passed

5. **Verified in the running app** — dev server against the local Postgres, with
   schedule 3 narrowed to Mon-Fri 09:00-17:00 and a Saturday 2026-09-19
   20:00-22:00 override added, then restored.
   - Booker confirm step: info Alert "Outside usual hours" rendered above an
     **enabled** Confirm button on the override slot; absent on a Monday 11:00 slot.
   - Bookings list: orange "Outside working hours" badge on the Saturday booking,
     absent on the Monday one, and absent throughout the Past tab.

## In Progress

## Blocked

## Next Steps

All slices complete and verified in the app.

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
- **Running the app caught a bug the tests did not.** Slice 3 read
  `eventType.schedule` directly, which is `null` for any event type that inherits
  the user's default schedule - the common case, and true of every seeded event
  type here. The guard then skipped flagging silently, so the booker Alert never
  appeared while every unit test still passed. Fixed by resolving the schedule
  through `detectEventTypeScheduleForUser`'s precedence chain (event type -> host
  -> user default) in a new `getScheduleForWorkingHours`, which returns null
  rather than letting the synthetic `DEFAULT_SCHEDULE_DATA` Mon-Fri 9-5 stand in
  as a baseline. Flagging is also limited to single-host events, since "the
  working hours" is ambiguous with several hosts. Covered by 5 new tests.
- Slice 4 done. The lookup helper mirrors `isTimeslotAvailable.ts`, including its
  look-either-side-of-the-date handling: the booker's timezone can file a slot
  under the previous or next date key. Threaded through `Booker.tsx` the way
  `isTimeslotUnavailable` already is, and added to the `EventBooker` useMemo deps
  so the notice does not go stale.
