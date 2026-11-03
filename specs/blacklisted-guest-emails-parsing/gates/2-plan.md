Outcome: continue

# Phase 2 — Plan gate

Spec: `specs/blacklisted-guest-emails-parsing/`
Base branch: `main` (given by `--base`; working branch `agent/issue-61`)

## Slices

1. **A booker on a comma-and-space blocklist is rejected** — new `packages/lib/getBlacklistedGuestEmails.ts` + its unit test, `checkIfBookerEmailIsBlocked.ts` switched to it, new booking-validations test.
2. **Blocklisted guests dropped with the forgiving parse** — `RegularBookingService.ts`.
3. **`addGuests` tRPC handler uses the shared parse** — `addGuests.handler.ts`, local `getBlacklistedEmails()` removed.
4. **Email-verification check uses the shared parse, session owner stays exempt** — `checkIfUserEmailVerificationRequired.handler.ts`, case-insensitive `!==` per design.md Edge Cases.

Size: 5 non-test files, 2 test files — one PR, within the `specs/README.md` limit.

## Verification

```sh
yarn test packages/lib/getBlacklistedGuestEmails.test.ts
yarn test packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts
```

## Assumptions

- Slices 3 and 4 get no new handler tests (none exist today and design.md declares none); they are covered by the helper's unit tests and type-check.
- No ADR: design.md already fixed the approach; no options were weighed in planning.
