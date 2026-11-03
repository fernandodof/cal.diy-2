# Blacklisted Guest Emails Parsing Design

## Overview

`BLACKLISTED_GUEST_EMAILS` is parsed in four places with a bare `.split(",")` and
no trimming, so an entry written as `a@spam.com, b@spam.com` (space after the
comma), with leading/trailing whitespace, or separated by a line break never
matches and the address is not blocked. Add one shared helper,
`getBlacklistedGuestEmails()` in `packages/lib/getBlacklistedGuestEmails.ts`,
that splits on commas and line breaks, trims, lowercases and drops empty entries,
and use it at all four call sites. Only parsing changes; who is blocked and what
happens to a blocked email stay as they are.

Ported from upstream calcom/cal.com#30460 (issue #61 in this fork).

## Problem Statement

An operator who writes the variable the natural way (`a@spam.com, b@spam.com`)
gets a blocklist where every entry after the first silently fails to match.
Nothing is logged, so the misconfiguration goes unnoticed and blocked addresses
can still book or be added as guests.

## User Stories

- As a self-hosting operator, I want `BLACKLISTED_GUEST_EMAILS` entries to match
  regardless of whitespace around them or a line break between them, so that the
  addresses I list are actually blocked.

## Acceptance Criteria

- [ ] Returns `[]` when the variable is unset or empty — `packages/lib/getBlacklistedGuestEmails.test.ts` › getBlacklistedGuestEmails returns an empty array when the variable is unset or empty
- [ ] `"a@spam.com,b@spam.com"` and `"a@spam.com, b@spam.com"` both return `["a@spam.com", "b@spam.com"]` — `packages/lib/getBlacklistedGuestEmails.test.ts` › getBlacklistedGuestEmails splits on commas with or without a space after them
- [ ] Leading and trailing whitespace is dropped (`"  a@spam.com  "` → `["a@spam.com"]`) — `packages/lib/getBlacklistedGuestEmails.test.ts` › getBlacklistedGuestEmails trims leading and trailing whitespace
- [ ] Entries are lowercased (`"A@Spam.com"` → `["a@spam.com"]`) — `packages/lib/getBlacklistedGuestEmails.test.ts` › getBlacklistedGuestEmails lowercases entries
- [ ] A newline works as a separator and empty entries are dropped (`"a@spam.com,\nb@spam.com,,"` → `["a@spam.com", "b@spam.com"]`) — `packages/lib/getBlacklistedGuestEmails.test.ts` › getBlacklistedGuestEmails splits on line breaks and drops empty entries
- [ ] A booking by a blocklisted email is rejected when the variable has a space after the comma (`"spam@test.com, blocked@example.com"` blocks `blocked@example.com`) — `packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts` › Booking Validation Specifications Email Blacklist Validation prevents booking when blacklisted email follows a comma and a space

## Technical Design

### Database Changes

None.

### API Changes

No endpoint or tRPC shape changes. Internal changes only:

**New helper** — `packages/lib/getBlacklistedGuestEmails.ts`

```ts
export const getBlacklistedGuestEmails = (): string[] =>
  (process.env.BLACKLISTED_GUEST_EMAILS ?? "")
    .split(/[,\r\n]+/)
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);
```

Reads the env at call time (not at module load), as every current call site
does, so tests that set `process.env` per test keep working. Imported as
`@calcom/lib/getBlacklistedGuestEmails`, the same way the call sites already
import `@calcom/lib/extract-base-email`.

**Call sites** (each verified by reading the file):

1. `packages/features/bookings/lib/handleNewBooking/checkIfBookerEmailIsBlocked.ts`
   (lines 20–26) — replace the inline split with the helper. The
   `.find((guestEmail) => guestEmail.toLowerCase() === baseEmail.toLowerCase())`
   only uses the result as a boolean (`!!blacklistedByEnv`), so it can stay as is
   or become `.includes(baseEmail.toLowerCase())`; either is the same set of
   blocked emails.
2. `packages/features/bookings/lib/service/RegularBookingService.ts`
   (lines 1219–1221, used at 1236) — replace the inline split; the
   `.some((e) => e.toLowerCase() === baseGuestEmail)` check is unchanged in effect.
3. `packages/trpc/server/routers/viewer/bookings/addGuests.handler.ts`
   (local `getBlacklistedEmails()` at lines 166–170, called at 207) — delete the
   local function and call the shared helper. It already lowercases and compares
   with `.includes(baseGuestEmail)`, so only the trimming/newline handling is new.
4. `packages/trpc/server/routers/publicViewer/checkIfUserEmailVerificationRequired.handler.ts`
   (lines 23–34) — replace the inline split. See Edge Cases for the
   `blacklistedEmail !== userSessionEmail` comparison.

**Tests**

- New `packages/lib/getBlacklistedGuestEmails.test.ts`, following
  `packages/lib/array.test.ts`: `import { describe, it, expect } from "vitest"`,
  one `describe("getBlacklistedGuestEmails")`, each test sets and then clears
  `process.env.BLACKLISTED_GUEST_EMAILS`.
- Extend `packages/features/bookings/lib/handleNewBooking/test/booking-validations.test.ts`
  inside `describe("Email Blacklist Validation")` (line 72), next to the two
  existing tests (lines 73 and 150). The file's `addToBlacklistedEmails` helper
  (line 52) builds the value with `emails.join(",")`, so the new test sets
  `process.env.BLACKLISTED_GUEST_EMAILS = "spam@test.com, blocked@example.com"`
  directly; the file's `afterEach` → `resetBlacklistedEmails()` (lines 56–58, 64–67)
  already clears it. The new test mirrors the existing "prevents booking when
  blacklisted email is not verified in the system" test (unverified organizer,
  booker `blocked@example.com`) and expects
  `"Cannot use this email to create the booking."`.

### UI Changes

None.

## Edge Cases

- **Unset / empty variable** → `[]`, same as today's `: []` branch.
- **Mixed-case entries** — two call sites (`checkIfBookerEmailIsBlocked`,
  `RegularBookingService`) already compared case-insensitively and
  `addGuests.handler.ts` already lowercased, so lowercasing in the helper does
  not change who is blocked there.
- **`checkIfUserEmailVerificationRequired.handler.ts` line 31** compares the
  *found entry* to the session email with a case-sensitive `!==`
  (`blacklistedEmail !== userSessionEmail`). Today the entry keeps the casing it
  was written with; after the helper it is lowercase. If an operator wrote
  `Foo@x.com` and the logged-in session email is `Foo@x.com`, today that user is
  not asked to verify; with a lowercased entry and an unchanged `!==` they would
  be. To keep the logged-in owner exempt, compare case-insensitively
  (`blacklistedEmail !== userSessionEmail?.toLowerCase()`), matching the
  `toLowerCase()` comparison the same handler already uses for the
  `requiresBookerEmailVerification` branch at line 40. Assumption recorded in the
  gate file.
- **Whitespace-only or trailing separators** (`"a@spam.com,,"`, `"\n"`) → empty
  entries dropped, so an empty string never matches anything.
- **Windows line endings** — splitting on `\r` as well as `\n` (or trimming,
  which removes `\r`) keeps `\r\n` from leaving a stray character.

## Out of Scope

- `.env.example` (line 398 declares `BLACKLISTED_GUEST_EMAILS=`) and
  `turbo.json` (line 19 lists it as a passthrough env) — not changed; the issue
  puts `.env.example` and other variables out of scope.
- Any change to *who* is blocked or *what happens* to a blocked email (error
  codes, guest removal, verification-code flow). Only parsing changes.
- Logging a warning for malformed entries.
- Review size: 1 new source file + 4 edited call sites (5 non-test files, well
  under 500 lines), within the `specs/README.md` rule of max 5–7 files per PR —
  one PR.
