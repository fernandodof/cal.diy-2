Outcome: continue

# Phase 1 — Research gate

Spec: `specs/blacklisted-guest-emails-parsing/`

## Overview

`BLACKLISTED_GUEST_EMAILS` is parsed in four places with a bare `.split(",")` and
no trimming, so entries written with a space after the comma, surrounding
whitespace, or a line break never match and the address is not blocked. Add one
shared helper, `getBlacklistedGuestEmails()` in
`packages/lib/getBlacklistedGuestEmails.ts`, that splits on commas and line
breaks, trims, lowercases and drops empty entries, and use it at all four call
sites. Only parsing changes; who is blocked and what happens to a blocked email
stay as they are.

## Files

New:

- `packages/lib/getBlacklistedGuestEmails.ts`
- `packages/lib/getBlacklistedGuestEmails.test.ts`

Modified:

- `packages/features/bookings/lib/handleNewBooking/checkIfBookerEmailIsBlocked.ts` (lines 20–26)
- `packages/features/bookings/lib/service/RegularBookingService.ts` (lines 1219–1221, used at 1236)
- `packages/trpc/server/routers/viewer/bookings/addGuests.handler.ts` (local `getBlacklistedEmails()` at 166–170, called at 207 — removed)
- `packages/trpc/server/routers/publicViewer/checkIfUserEmailVerificationRequired.handler.ts` (lines 23–34)
- `packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts` (new test in `describe("Email Blacklist Validation")`, line 72)

Read, not modified:

- `packages/lib/array.test.ts` (test convention reference)
- `.env.example` line 398, `turbo.json` line 19 (out of scope)
- `specs/README.md` (review-size rule: 5 non-test files, one PR)

## Open questions and assumptions

1. **Case-sensitive session comparison in `checkIfUserEmailVerificationRequired.handler.ts:31`.**
   It compares the found blocklist entry to the session email with `!==`. Today
   the entry keeps its written casing; after the helper it is lowercase, so an
   operator entry `Foo@x.com` with session `Foo@x.com` would newly require
   verification. **Assumption:** compare case-insensitively
   (`blacklistedEmail !== userSessionEmail?.toLowerCase()`), matching the
   `toLowerCase()` comparison the same handler already uses at line 40. This
   keeps the logged-in owner exempt, which is the existing intent.
2. **Separator regex.** The issue says "commas and line breaks". **Assumption:**
   split on `/[,\r\n]+/` and trim, so `\r\n` and runs of separators work; empty
   entries are filtered afterwards regardless.
3. **Spaced booking test shape.** The file's `addToBlacklistedEmails` helper uses
   `emails.join(",")`. **Assumption:** the new test sets
   `process.env.BLACKLISTED_GUEST_EMAILS = "spam@test.com, blocked@example.com"`
   directly (the existing `afterEach` clears it) rather than changing the helper,
   and mirrors the existing unverified-user test, expecting
   `"Cannot use this email to create the booking."`. Test name:
   "prevents booking when blacklisted email follows a comma and a space".
