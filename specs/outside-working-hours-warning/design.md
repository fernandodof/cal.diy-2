# Outside Working Hours Warning Design

## Overview

Surface a passive, non-blocking notice when a booking falls outside the host's
recurring weekly availability — that is, when the slot exists only because a
date override opened it. Two surfaces: the booker's confirm step, and the host's
upcoming bookings list.

## Problem Statement

A date override is merged into the host's bookable time, so a slot it opens is
indistinguishable from a normal-hours slot at every downstream surface. The
booker cannot tell that 8pm Saturday was a grudging exception, and the host
scanning their upcoming list cannot tell which bookings landed outside their
usual pattern. Nothing in the codebase currently expresses "bookable, but
unusual" — the model is binary.

## User Stories

- As someone booking, I want to be told when the time I picked falls outside the
  host's usual hours so that I can reconsider before confirming.
- As a host, I want my upcoming bookings list to flag bookings that landed
  outside my usual hours so that I can spot them at a glance.

## Technical Design

### The signal: provenance, not time-of-day

"Outside working hours" means **the slot came from a date override**, not that
the hour is late. No time-of-day heuristic, no configurable threshold.

The distinction is already drawn in the data. `Availability`
(`packages/prisma/schema.prisma:960`) holds both kinds of row and discriminates
on `date`:

- recurring weekly: `date == null`, `days` non-empty
- date override: `date != null`

`getWorkingHours` filters on exactly this, with the comment
`// Include only recurring weekly availability, not date overrides`
(`packages/lib/availability.ts:76-77`).

**The baseline must not be `dateRanges`.** `buildDateRanges`
(`packages/features/schedules/lib/date-ranges.ts:226`) merges overrides into
`dateRanges`, and the booking gate `hasDateRangeForBooking`
(`packages/features/bookings/lib/handleNewBooking/ensureAvailableUsers.ts:37-55`)
checks containment against those merged ranges. So every bookable slot is inside
`dateRanges` by construction, and a comparison against it can never fire.

### Database Changes

None. No schema change, no migration, no new `Booking` column. The flag is
computed, never stored.

### API Changes

**Surface 2 — bookings list.** `getHandler`
(`packages/trpc/server/routers/viewer/bookings/get.handler.ts:40`) returns
`{ bookings, recurringInfo, totalCount, nextCursor }`, with `bookings` coming
from `getAllUserBookings` (`packages/features/bookings/lib/getAllUserBookings.ts`).
Add a computed boolean per booking to that payload.

- The tab is known at `get.handler.ts:57-59` via `bookingListingByStatus`, so the
  computation is skipped unless `upcoming` is among the requested statuses.
- Reference schedule is **the viewer's own** — `ctx.user` is available at
  `get.handler.ts:54`; `User.defaultScheduleId` is at
  `packages/prisma/schema.prisma:428`. This holds for team and collective events
  too: it is the viewer's list, so it reflects the viewer's hours.
- Fetch the viewer's recurring `Availability` rows **once per request**, not per
  booking, then test each booking's `startTime`/`endTime` against them.

**Surface 1 — booker.** The slots path currently hardcodes
`returnDateOverrides: false` (`packages/trpc/server/routers/viewer/slots/util.ts:816`),
so override provenance never reaches the booker. Flip it to `true` and mark each
returned slot that falls outside the recurring rows.

The slot output reducer destructures `{ time, ...passThroughProps }` and spreads
`passThroughProps` into each emitted slot (`slots/util.ts:1267-1291`), so a field
attached to a slot upstream reaches the client without changing that reducer.
The client-facing slot type at `slots/util.ts:1269` gains one optional boolean
alongside `attendees` and `bookingUid`.

### UI Changes

**Booker confirm step.** `apps/web/modules/bookings/components/BookEventForm/BookEventForm.tsx`.
The file already imports `Alert` from `@calcom/ui/components/alert` (line 13) and
renders a chained ternary of alerts ending at line 175: form errors (line 137),
then `isTimeslotUnavailable` (line 155), then `null`. Add a further branch to
that chain.

- `severity="info"`, matching both existing alerts (lines 140 and 156) — the
  established convention in this flow, used even for the hard-blocking
  unavailable-slot case.
- Passive: the confirm button stays enabled. No checkbox, no second click.
- Because the chain is exclusive, an unavailable slot suppresses this notice.
  That is the correct precedence — a blocking error outranks an advisory one.

**Bookings list row.** `apps/web/components/booking/BookingListItem.tsx:130`,
fed by `apps/web/modules/bookings/hooks/useBookingListColumns.tsx:127`. The row
reads the boolean from its props and renders a marker near the existing time
display (desktop lines 297-305, mobile 349-359). No fetching in the row.

**i18n.** One new snake_case key in `packages/i18n/locales/en/common.json`
(English only; other locales fill in later), read via `useLocale` from
`@calcom/lib/hooks/useLocale`. Neighbours: `unavailable_timeslot_title` (L134).

### Files expected to change

| File | Change |
|---|---|
| `packages/trpc/server/routers/viewer/bookings/get.handler.ts` | compute the flag for upcoming bookings |
| `apps/web/modules/bookings/hooks/useBookingListColumns.tsx` | thread the flag to the row |
| `apps/web/components/booking/BookingListItem.tsx` | render the marker |
| `apps/web/modules/bookings/components/BookEventForm/BookEventForm.tsx` | add the Alert branch |
| `packages/i18n/locales/en/common.json` | new key(s) |
| `packages/trpc/server/routers/viewer/slots/util.ts` | flag override-derived slots |
| `packages/features/bookings/lib/isOutsideRecurringHours.ts` (new) | shared predicate |

Seven files excluding tests, at the top of the 5-7 limit in `specs/README.md:77-81`.
If it grows past that during Phase 3, the booker surface (slices 3-4) splits into
a second PR.

## Resolved — how the booker learns the slot is an override

The task brief assumed `dateOverrides` was already available to the booker via
`getUserAvailability`. **It was not.** The slots path hardcoded
`returnDateOverrides: false` (`slots/util.ts:816`), and `grep` for `dateOverrides`
across `packages/features/bookings/Booker/` and the slots router returned nothing;
the only caller passing `true` is the host-facing
`packages/trpc/server/routers/viewer/availability/user.handler.ts:27`.

**Decision: flag slots server-side (option A).** Recorded as ADR-001 in
`decisions.md`.

## Edge Cases

- **Host has no schedule / no recurring rows.** `DEFAULT_SCHEDULE_DATA`
  (`packages/features/availability/lib/detectEventTypeScheduleForUser.ts:13`) is
  Mon-Fri 09:00-17:00 UTC. Treat a host with no recurring rows as having no
  baseline and flag nothing, rather than flagging everything against a default
  the host never chose.
- **Zero-length override** (`startTime == endTime`) encodes "day blocked"
  (`date-ranges.ts:295-303`) and produces no bookable slot, so it can never be
  flagged.
- **Timezone.** Recurring rows store time-of-day as UTC wall-clock, read via
  `getUTCHours()`/`getUTCMinutes()`, and the comparison must be done in the
  schedule's timezone (`Schedule.timeZone` is nullable, falling back to the
  user's). `yarn test` pins `TZ=UTC`, so tests must set their zone explicitly.
- **Booking spanning a boundary** — starts inside recurring hours, ends outside.
  Treat as outside only if it is not fully contained, mirroring the containment
  semantics of `hasDateRangeForBooking`.
- **Schedule changes after booking.** The flag is a live read, so deleting an
  override un-flags upcoming bookings. Accepted deliberately.
- **Cancelled/rejected bookings** in the upcoming tab should not be flagged.

## Out of Scope

- No durable/historical record — no `Booking` column, no persistence. The flag
  is recomputed on read and only meaningful for upcoming bookings.
- No time-of-day heuristic and no user-configurable "working hours" setting.
- No new settings UI.
- No slot-grid annotation (`AvailableTimes.tsx` untouched) — confirm step only.
- No blocking, no confirmation friction; the booking flow is never gated.
- Past bookings are not flagged.
- Not built on `getWorkingHours`/`workingHours`
  (`packages/lib/availability.ts:61`): despite the name it is legacy — nothing in
  the booking or slot-generation path reads it, and several handlers hardcode it
  to `[]` (e.g. `packages/trpc/server/routers/viewer/availability/schedule/getScheduleByUserId.handler.ts:50`).
  The recurring-row filter it performs is the part worth reusing.
</content>
</invoke>
