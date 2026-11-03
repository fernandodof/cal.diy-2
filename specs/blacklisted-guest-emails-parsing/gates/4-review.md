Outcome: continue

Review of `git diff origin/main...HEAD` (fixed point `origin/main` = 379fd1fe89). Spec: `specs/blacklisted-guest-emails-parsing/design.md` + issue #61 text. Standards: `CONTRIBUTING.md` + smell baseline.

## Standards

No hard violations found against `CONTRIBUTING.md`:
- **File naming:** the rules cover class-based Service and Repository files only. `packages/lib/getBlacklistedGuestEmails.ts` is a camelCase util, the same as the `getAvatarUrl.ts` and `getIP.ts` files next to it, and the test uses the `.test.ts` suffix the guide allows.
- **PR size:** the limit is under 500 changed lines and under 10 code files. This branch changes 7 code files and about 120 lines of code, and the specs/ files don't count.

Skipped because biome handles them (organizeImports, `noProcessGlobal`): the import reordering, `import process from "node:process"`, and the missing blank line in the new helper.

**Judgement calls (baseline smells):**

1. **Possible Duplicated Code: the same "is this email blocklisted" match in three places.**
   - `packages/features/bookings/lib/handleNewBooking/checkIfBookerEmailIsBlocked.ts:21`: `getBlacklistedGuestEmails().find((guestEmail: string) => guestEmail.toLowerCase() === baseEmail.toLowerCase())`
   - `packages/trpc/server/routers/publicViewer/checkIfUserEmailVerificationRequired.handler.ts:23`: `getBlacklistedGuestEmails().find((guestEmail: string) => guestEmail === baseEmail.toLowerCase())`
   - `packages/features/bookings/lib/service/RegularBookingService.ts:1239` (existing line, not in the diff): `blacklistedGuestEmails.some((e) => e.toLowerCase() === baseGuestEmail)`

   The helper already lowercases every entry, so the `guestEmail.toLowerCase()` and `e.toLowerCase()` calls do nothing now. Only the handler dropped its extra call, so the three call sites no longer match each other. One option is a small predicate such as `isBlacklistedGuestEmail(email)` next to the helper. Another is to at least remove the extra lowercasing so all three read the same.

2. **Possible Primitive Obsession (weak): the helper's `string[]` relies on an unstated rule.** At `packages/lib/getBlacklistedGuestEmails.ts:2` the returned list is "already trimmed and lowercased", but neither the type nor a comment says so. That is why item 1 happened: callers can't tell, so they lowercase again. A one-line comment would match how much the surrounding code comments. A new type would be too much here.

3. **Possible Duplicated Code in the new test:** `booking-validations.test.ts:208-266`. The new test copies about 60 lines of organizer, scenario and request setup from the test above it. The other tests in this file are written the same verbose way, so this matches the file and is minor. Separately, line 227 sets `process.env.BLACKLISTED_GUEST_EMAILS = "spam@test.com, blocked@example.com"` directly instead of calling the file's `addToBlacklistedEmails` helper (line 48). That is reasonable, since the helper joins with `","` and can't produce the `", "` separator under test, but a short comment saying so would help.

**Positive:** the new unit test `packages/lib/getBlacklistedGuestEmails.test.ts` follows the `describe`/`it` style of `packages/lib/array.test.ts`. Moving the private `getBlacklistedEmails` out of `addGuests.handler.ts` into the shared helper removes an earlier duplicate rather than adding one.

## Spec

**(a) Missing or partial**

1. **judgement**: Issue constraint: "Follow `packages/lib/array.test.ts`: `import { describe, it, expect } from "vitest"` … Set and clear `process.env.BLACKLISTED_GUEST_EMAILS` in each test." At `packages/lib/getBlacklistedGuestEmails.test.ts:1-9` the vitest import also brings in `afterEach` and adds `import process from "node:process"`. The variable is cleared in a shared `afterEach`, not in each test. The behaviour is the same, but it doesn't follow the stated pattern. design.md repeats the issue's wording ("each test sets and then clears"), and the code matches neither.

Everything else is done. The helper sits at `packages/lib/getBlacklistedGuestEmails.ts` and is used at all four call sites. The local `getBlacklistedEmails()` in `addGuests.handler.ts` is deleted. Each acceptance criterion has a matching test, and the spaced booking test sits next to the existing blocklist tests (`booking-validations.test.ts:208`).

**(b) Scope creep**

2. **judgement**: The issue says "Only the parsing changes." The diff also re-sorts and merges the existing imports and removes the blank lines between them at `booking-validations.test.ts:5-22`. It adds `import process from "node:process"` there and in the helper (`getBlacklistedGuestEmails.ts:1`), and removes a blank line in `checkIfUserEmailVerificationRequired.handler.ts:5`. This looks like a biome autofix on code the task didn't touch.
3. **judgement (minor)**: The test file adds a `\r\n` case at `getBlacklistedGuestEmails.test.ts:41-42`, which no criterion asks for. It is covered by the design's "Windows line endings" edge case, so it is harmless.

**(c) Implemented but possibly wrong**

4. **judgement**: The issue says "Don't change who is blocked or what happens to a blocked email." The session-email exemption at `checkIfUserEmailVerificationRequired.handler.ts:27` changed from `blacklistedEmail !== userSessionEmail` to `!== userSessionEmail?.toLowerCase()`. design.md (Edge Cases) argues this is needed to keep the exemption. But it also widens the exemption where main was strict. Example: the entry is `foo@x.com` and the session email is `Foo@x.com`. On main, `"foo@x.com" !== "Foo@x.com"` is true, so that user must verify. On this branch they are exempt.

   Lowercasing in the helper makes exact preservation impossible. Still, design.md says the result is "the same set" and not a change in behaviour, which hides this. The issue's "only parsing changes" rule and design.md's choice disagree here, so this should be called out in the PR.
5. **judgement (minor)**: `log.warn` at `checkIfUserEmailVerificationRequired.handler.ts:28` now logs the lowercased entry, not the casing the operator wrote. Logging is otherwise unchanged.

Checked and preserved:
- `checkIfBookerEmailIsBlocked.ts:21` and `RegularBookingService.ts:1237`: the case-insensitive comparisons are unchanged.
- `addGuests.handler.ts:216`: `.includes` still works on lowercased entries.
- Error messages, guest filtering and the verification-code flow are unchanged.

**design.md compared with the issue:** The only divergence is item 4. design.md treats the case-insensitive session comparison as keeping behaviour, but it relaxes the main-branch check in the case above. Out of scope (`.env.example`, other variables) matches the issue.

---

Summary: Standards: 3 findings, all judgement-call smells (worst: the redundant, now-inconsistent lowercasing across the three blocklist match sites). Spec: 5 findings, all judgement (worst: the session-email exemption in `checkIfUserEmailVerificationRequired.handler.ts:27` now compares case-insensitively, which slightly widens who is exempt compared with main).
