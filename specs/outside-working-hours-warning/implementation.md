# Outside Working Hours Warning Implementation

## Status: in-progress

## Completed

## In Progress

## Blocked

## Next Steps

1. **The predicate exists and is correct in isolation** — proves the
   recurring-vs-override rule, including the timezone handling that everything
   else depends on. A booking time plus a set of `Availability` rows yields a
   correct boolean.
   - `packages/features/bookings/lib/isOutsideRecurringHours.ts` (new)
   - `packages/features/bookings/lib/isOutsideRecurringHours.test.ts` (new)
   - Verified by: `yarn test packages/features/bookings/lib/isOutsideRecurringHours.test.ts`
   - Must cover: recurring-only rows (never outside), override-created times
     (outside), a booking spanning the boundary (outside, mirroring
     `hasDateRangeForBooking` containment), a host with no recurring rows
     (nothing flagged), and a non-UTC schedule timezone with the zone set
     explicitly — `yarn test` pins `TZ=UTC`.

2. **A host's upcoming list flags an override booking, end to end** — proves
   server compute → payload → row render. This is the thinnest complete path and
   uses data already in reach.
   - `packages/trpc/server/routers/viewer/bookings/get.handler.ts`
   - `apps/web/modules/bookings/hooks/useBookingListColumns.tsx`
   - `apps/web/components/booking/BookingListItem.tsx`
   - `packages/i18n/locales/en/common.json`
   - Verified by: `yarn test packages/trpc/server/routers/viewer/bookings/get.handler.test.ts`,
     plus loading the bookings list with an override-created booking
   - Skip the computation unless `upcoming` is among `bookingListingByStatus`
     (`get.handler.ts:57-59`); fetch the viewer's recurring rows once per
     request, never per booking; exclude cancelled/rejected.

3. **A slot carries its override provenance to the client** — proves the
   availability → slots → wire path that slice 4 renders.
   - `packages/trpc/server/routers/viewer/slots/util.ts`
   - Verified by: `yarn test packages/trpc/server/routers/viewer/slots/util.test.ts`,
     plus inspecting the slots response for a schedule with a date override
   - Flip `returnDateOverrides` to `true` (line 816); attach the flag so it rides
     `passThroughProps` (lines 1267-1291); add the optional boolean to the slot
     type at line 1269. Emit the field only when true.

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
</content>
