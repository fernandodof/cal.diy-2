Outcome: continue

# Fix round — blacklisted guest emails parsing (#61)

This round fixed the spec findings of kind `missing` or `wrong` from
`.agent-handoff/review.json`. It did not touch the creep or standards findings.

## 1. wrong — session-email exemption casing

> `checkIfUserEmailVerificationRequired.handler.ts:27`: the exemption compared
> against `userSessionEmail?.toLowerCase()`, which exempts a session email whose
> casing differs from the entry. On `main` that case required verification.

**Change:** `packages/lib/getBlacklistedGuestEmails.ts` now also exports
`getBlacklistedGuestEmailsAsWritten()`. It splits on commas and line breaks,
trims, and drops empty entries, but does not lowercase.
`getBlacklistedGuestEmails()` is now that result mapped to lowercase. The handler
uses the as-written variant with `main`'s match,
`guestEmail.toLowerCase() === baseEmail.toLowerCase()`, and `main`'s exemption,
`blacklistedEmail !== userSessionEmail`. The design's Edge Cases note has been
revised to match.

## 2. wrong — warning logs the lowercased entry

> `checkIfUserEmailVerificationRequired.handler.ts:28`: `log.warn` logged the
> lowercased entry instead of the operator's casing.

**Change:** fixed by the same change as #1. `blacklistedEmail` is the entry as
written again, so the log line is identical to `main`.

## 3. missing — unit-test setup

> `getBlacklistedGuestEmails.test.ts:1-9`: a shared `afterEach` and extra
> `afterEach` / `node:process` imports, instead of setting and clearing the env
> var in each test with only `{ describe, it, expect }` from vitest.

**Change:** I removed the `afterEach` and the `node:process` import. The vitest
import is now `import { describe, it, expect } from "vitest"`, as in
`packages/lib/array.test.ts`. Each test sets and then clears
`process.env.BLACKLISTED_GUEST_EMAILS` itself. I added a
`describe("getBlacklistedGuestEmailsAsWritten")` with one test, plus a matching
acceptance criterion in `design.md`. It is in the same test file, so the
`## Verification` block does not change.

## Checks

- `yarn test packages/lib/getBlacklistedGuestEmails.test.ts` — 6 passed
- `yarn test packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts` — 15 passed
- `yarn tsc --noEmit -p packages/trpc/tsconfig.json` — 0 errors
- `yarn biome lint` on the three changed source/test files — 0 errors. There are
  `noProcessEnv`/`noProcessGlobal` warnings from using `process.env` directly in
  tests, which the spec asks for.
