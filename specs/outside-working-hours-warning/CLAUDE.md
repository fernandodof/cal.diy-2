# CLAUDE.md — Outside Working Hours Warning

## Project Context

A passive notice shown when a booking falls outside the host's recurring weekly
availability — i.e. the slot exists only because a date override opened it.
Appears on the booker's confirm step and on the host's upcoming bookings list.
Nothing is blocked and nothing is persisted.

## Before Starting Work

1. Read specs/outside-working-hours-warning/design.md
2. Check specs/outside-working-hours-warning/implementation.md for current progress
3. Look at existing patterns in:
   - `packages/lib/availability.ts` (recurring vs. override filtering)
   - `apps/web/modules/bookings/components/BookEventForm/` (the Alert chain)
   - `packages/trpc/server/routers/viewer/bookings/` (handler + test style)

## Code Patterns

- **The signal is provenance, not time-of-day.** A slot is "outside working
  hours" because a date override created it, never because the hour is late.
- **Discriminate on `date`**: an `Availability` row is an override iff
  `date != null`, recurring iff `date == null` and `days` is non-empty. See
  `packages/lib/availability.ts:76-77`.
- **Never compare against `dateRanges`** — `buildDateRanges` merges overrides in,
  so every bookable slot is inside it and the check can never fire. Compare
  against the recurring rows only.
- Reuse `Alert` from `@calcom/ui/components/alert` with `severity="info"`,
  matching the existing alerts in `BookEventForm.tsx` (lines 140, 156).
- Batch the schedule lookup once per request; never fetch per booking row.
- Timezone-sensitive tests must set their zone explicitly — `yarn test` pins
  `TZ=UTC`.

## Don't

- Don't add features not in design.md
- Don't skip tests
- Don't add a `Booking` column or otherwise persist the flag — it is a live read
- Don't build on `getWorkingHours`/`workingHours` (`packages/lib/availability.ts:61`);
  it is legacy and unread by the booking path
- Don't block or gate the booking flow, and don't disable the confirm button
- Don't annotate the slot grid (`AvailableTimes.tsx`) — confirm step only
- Don't flag past bookings
