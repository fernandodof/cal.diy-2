# Outside Working Hours Warning Decisions

## ADR-001: Flag override-derived slots server-side in the slots endpoint

### Context

The booker's confirm step needs to know whether the selected slot exists only
because of a date override. Research found the data does not reach the booker:
`packages/trpc/server/routers/viewer/slots/util.ts:816` hardcodes
`returnDateOverrides: false`, and no reference to `dateOverrides` exists anywhere
under `packages/features/bookings/Booker/` or the slots router. The only caller
requesting overrides is the host-facing availability endpoint
(`packages/trpc/server/routers/viewer/availability/user.handler.ts:27`).

### Options Considered

1. **Flag slots server-side** — set `returnDateOverrides: true` in the slots
   path and attach a boolean to each override-derived slot. Shares one predicate
   with the bookings-list surface and keeps the logic beside the availability
   computation. Costs: touches a hot endpoint, and adds a field to every slot in
   the payload.
2. **Ship the host-list surface only** — smaller, safer PR; the booker notice
   becomes follow-up work. Risk: the booker half is the half the user asked for
   first, and deferring it likely means it never lands.

### Decision

Option 1, but **without flipping `returnDateOverrides`** — which the plan had
assumed was necessary and which implementation showed it is not.

Reading `getUserAvailability` more closely, the raw `availability` rows are loaded
at line 415 regardless of that flag; `returnDateOverrides` gates only the extra
transformation loop at lines 442-464. The comment above it
(`getUserAvailability.ts:439-441`) says `getSchedule` already calls this for every
user of a team event without using the values, and the flag exists specifically to
avoid that wasted CPU. Setting it to `true` would have reintroduced exactly the
cost that guard was added to prevent, per user, per team event.

Instead the slots path flags slots from data it already has:
`eventTypeRepository.findForSlots` (lines 1312-1325) already selects
`schedule.availability` with `date`, `startTime`, `endTime` and `days`, plus
`schedule.timeZone`. The flag is computed after `getSlots` and rides the existing
`passThroughProps` spread in the slot reducer.

### Consequences

- The recurring-vs-override predicate is extracted to a shared module so the
  slots path and the bookings-list handler compute the flag identically.
- The slots response grows by one optional boolean per slot; only present when
  true, to keep the common case unchanged on the wire.
- **No change to `returnDateOverrides`, no extra query, and no new per-user work
  in the team-event path** — the schedule rows were already being fetched.
- The event type's schedule is the reference on the booker side, which is the
  right one there: the booker is looking at one event type's availability. The
  bookings list uses the viewer's own schedule instead, since that surface
  answers a different question.
- File count reaches seven excluding tests, at the top of the review-size rule in
  `specs/README.md:77-81`. If Phase 3 exceeds it, the booker surface splits into
  a second PR.
</content>
