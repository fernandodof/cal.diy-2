# Blacklisted Guest Emails Parsing Implementation

## Status: complete

## Completed

1. **A booker on a comma-and-space blocklist is rejected** — proves helper → `checkIfBookerEmailIsBlocked` → `handleNewBooking` path end to end
   - New `packages/lib/getBlacklistedGuestEmails.ts` (as in design.md › API Changes)
   - New `packages/lib/getBlacklistedGuestEmails.test.ts` — the five helper criteria in design.md, one `describe("getBlacklistedGuestEmails")`, env set and cleared per test
   - `packages/features/bookings/lib/handleNewBooking/checkIfBookerEmailIsBlocked.ts` (lines 20–26) — replace the inline split with the helper
   - `packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts` — add "prevents booking when blacklisted email follows a comma and a space" inside `describe("Email Blacklist Validation")`, mirroring the test at line 150
   - Verified by: `yarn test packages/lib/getBlacklistedGuestEmails.test.ts`, `yarn test packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts`
2. **Blocklisted guests are dropped from a new booking with the forgiving parse** — proves the guest-filter path in the booking service uses the helper
   - `packages/features/bookings/lib/service/RegularBookingService.ts` (lines 1219–1221, used at 1238) — replace the inline split; keep the `.some(...)` check
   - Verified by: `yarn test packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts` (existing suite stays green), plus `yarn tsc --noEmit -p packages/features/tsconfig.json` (errors in changed files only — the project is not clean on `main`)

3. **Adding a guest to an existing booking uses the shared parse** — proves the tRPC `addGuests` path
   - `packages/trpc/server/routers/viewer/bookings/addGuests.handler.ts` — delete the local `getBlacklistedEmails()` (lines 166–170) and call the helper at line 207
   - Verified by: `yarn tsc --noEmit -p packages/trpc/tsconfig.json` (errors in changed files only); no existing `addGuests` test file (checked `packages/trpc/server/routers/viewer/bookings/`)

4. **Email-verification check uses the shared parse and keeps the session owner exempt** — proves the public tRPC path
   - `packages/trpc/server/routers/publicViewer/checkIfUserEmailVerificationRequired.handler.ts` (lines 23–34) — replace the inline split; compare `blacklistedEmail !== userSessionEmail?.toLowerCase()` (design.md › Edge Cases)
   - Verified by: `yarn tsc --noEmit -p packages/trpc/tsconfig.json` (errors in changed files only); no existing test for this handler (checked `packages/trpc/server/routers/publicViewer/`)

## In Progress

## Blocked

## Next Steps

Every file in design.md's call-site and test lists is covered: 1 new source file + 4 edited call sites (5 non-test files) and 2 test files — within the `specs/README.md` limit (5–7 files, 500 lines). One PR.

## Verification

```sh
yarn test packages/lib/getBlacklistedGuestEmails.test.ts
yarn test packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts
```

## Session Notes

- Base branch: `main` (from `--base main`; the harness created and checked out `agent/issue-61`).
- Slices 3 and 4 have no existing test file to extend; design.md declares no new tests for them, so they rely on the helper's unit tests plus type-check. Adding handler tests would be scope beyond design.md.
- Slice 1 done: helper + unit tests, `checkIfBookerEmailIsBlocked` uses it. New booking test failed first (booking was accepted), passes now; 20/20 across both files. `biome check --write` also sorted the existing imports in `booking-validations.test.ts` and added `import process from "node:process"` (the pattern the call sites already use). Next: slice 2, `RegularBookingService`.
- Slice 2 done: `RegularBookingService` uses the helper. booking-validations 15/15; `tsc -p packages/features` reports no errors in the changed files (the project's other errors are pre-existing). Next: slice 3, `addGuests.handler.ts`.
- Slice 3 done: local `getBlacklistedEmails()` removed, handler calls the helper; the now-unused `import process from "node:process"` removed too. `tsc -p packages/trpc` reports 0 errors (`--listFiles` confirms the changed files are included). Next: slice 4, `checkIfUserEmailVerificationRequired.handler.ts`.
- Slice 4 done: handler uses the helper; since entries are now lowercase, the `find` compares against `baseEmail.toLowerCase()` and the owner exemption compares against `userSessionEmail?.toLowerCase()`. `tsc -p packages/trpc` 0 errors. Next: final checks, then the PR body.
- Final checks: getBlacklistedGuestEmails.test.ts 5/5, booking-validations.test.ts 15/15, `yarn turbo run type-check --filter=@calcom/web` passed (3/3 tasks, `@calcom/web:type-check` executed). PR body written to `.agent-handoff/pr-body.md` for the harness.
