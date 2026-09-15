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

Option 1. It is what the feature was scoped to do, and the payload cost is one
optional boolean on slots that are already being serialized. The slot reducer at
`slots/util.ts:1267-1291` destructures `{ time, ...passThroughProps }` and
spreads the rest into each emitted slot, so the field propagates to the client
without restructuring that code.

### Consequences

- The recurring-vs-override predicate is extracted to a shared module so the
  slots path and the bookings-list handler compute the flag identically.
- The slots response grows by one optional boolean per slot; only present when
  true, to keep the common case unchanged on the wire.
- `returnDateOverrides: true` makes `getUserAvailability` return override data in
  the slots path, which it previously skipped. Watch for a measurable cost on a
  hot endpoint; the override rows are already loaded to build `dateRanges`, so
  this is a serialization change rather than an extra query.
- File count reaches seven excluding tests, at the top of the review-size rule in
  `specs/README.md:77-81`. If Phase 3 exceeds it, the booker surface splits into
  a second PR.
</content>
