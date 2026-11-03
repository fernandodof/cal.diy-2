# CLAUDE.md — Blacklisted Guest Emails Parsing

## Project Context

One shared helper, `getBlacklistedGuestEmails()` in `packages/lib/`, replaces four
bare `.split(",")` parses of `BLACKLISTED_GUEST_EMAILS` so entries with
surrounding whitespace or line breaks still match. Issue #61, ported from
upstream calcom/cal.com#30460.

## Before Starting Work

1. Read specs/blacklisted-guest-emails-parsing/design.md
2. Check specs/blacklisted-guest-emails-parsing/implementation.md for current progress
3. Look at the four call sites listed in design.md, and at
   `packages/lib/extract-base-email` for how they import small `@calcom/lib` helpers

## Code Patterns

- Unit tests follow `packages/lib/array.test.ts`: `import { describe, it, expect } from "vitest"`,
  one `describe` per function
- Set and clear `process.env.BLACKLISTED_GUEST_EMAILS` inside each test; the helper
  must read the env at call time, not at module load
- Booking-level coverage goes in the existing `describe("Email Blacklist Validation")`
  in `packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts`

## Don't

- Don't add features not in design.md
- Don't skip tests
- Don't change who is blocked or what happens to a blocked email — parsing only
- Don't touch `.env.example`, `turbo.json`, or any other environment variable
