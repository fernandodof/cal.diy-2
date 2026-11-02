# Duration Type Tests Design

## Overview

Add unit tests for two pure helpers in `packages/lib/`:
`convertToNewDurationType` (convert a value between `minutes` / `hours` / `days`,
rounding up with `Math.ceil`) and `findDurationType` (pick the coarsest unit that
divides a minute value evenly). Tests only — neither function's behaviour changes.
Source: issue #11 (https://github.com/fernandodof/cal.diy-2/issues/11).

## Problem Statement

Neither `packages/lib/convertToNewDurationType.ts` nor
`packages/lib/findDurationType.ts` has a test (`ls packages/lib | grep -i duration`
lists only the two source files). Both are used by
`packages/features/eventtypes/components/tabs/limits/EventLimitsTab.tsx`, so a
regression in either changes how event-type limits are displayed and converted.
Pinning today's behaviour — including the two surprising parts, `Math.ceil`
rounding and `0` resolving to `"days"` — makes any later change deliberate.

## User Stories

- As a maintainer, I want the duration helpers covered by tests so that a change to
  their rounding or unit selection fails CI instead of silently altering event limits.

## Acceptance Criteria

- [ ] minutes → minutes returns the value unchanged — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType returns the value unchanged when converting minutes to minutes
- [ ] hours → hours returns the value unchanged — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType returns the value unchanged when converting hours to hours
- [ ] days → days returns the value unchanged — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType returns the value unchanged when converting days to days
- [ ] minutes → hours divides by 60 — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts minutes to hours
- [ ] minutes → days divides by 1440 — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts minutes to days
- [ ] hours → minutes multiplies by 60 — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts hours to minutes
- [ ] hours → days divides by 24 — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts hours to days
- [ ] days → minutes multiplies by 1440 — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts days to minutes
- [ ] days → hours multiplies by 24 — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts days to hours
- [ ] Uneven minutes → hours rounds up (90 → 2) — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType rounds up when minutes do not divide evenly into hours
- [ ] Uneven minutes → days rounds up — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType rounds up when minutes do not divide evenly into days
- [ ] Uneven hours → days rounds up — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType rounds up when hours do not divide evenly into days
- [ ] Zero input returns 0 for every pair — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType returns 0 for a zero value in every direction
- [ ] A value divisible by 1440 returns `"days"` — `packages/lib/findDurationType.test.ts` › findDurationType returns days for a value divisible by 1440
- [ ] A value divisible by 60 but not 1440 returns `"hours"` — `packages/lib/findDurationType.test.ts` › findDurationType returns hours for a value divisible by 60 but not by 1440
- [ ] Any other value returns `"minutes"` — `packages/lib/findDurationType.test.ts` › findDurationType returns minutes for a value not divisible by 60
- [ ] `0` returns `"days"` (current behaviour) — `packages/lib/findDurationType.test.ts` › findDurationType returns days for 0

## Technical Design

### Database Changes

None.

### API Changes

None.

### UI Changes

None.

### Files

Read (unchanged):

- `packages/lib/convertToNewDurationType.ts` — default export
  `convertToNewDurationType(prevType, newType, prevValue)`; exports
  `MINUTES_IN_HOUR = 60`, `MINUTES_IN_DAY = 1440`, `HOURS_IN_DAY = 24` and
  `type DurationType = "minutes" | "hours" | "days"`. Looks up
  `` `${prevType}_${newType}` `` in a map of nine functions and returns
  `Math.ceil(result)`.
- `packages/lib/findDurationType.ts` — default export `findDurationType(value)`:
  `value % 1440 === 0` → `"days"`, else `value % 60 === 0` → `"hours"`, else
  `"minutes"`.

Added:

- `packages/lib/convertToNewDurationType.test.ts` — one
  `describe("convertToNewDurationType")`.
- `packages/lib/findDurationType.test.ts` — one `describe("findDurationType")`.

Conventions, from `packages/lib/array.test.ts`: `import { describe, it, expect }
from "vitest";`, a blank line, then the relative import of the module under test
(`./convertToNewDurationType`, `./findDurationType` — both default exports), one
`describe` per function, plain `it(...)` blocks with `expect(...).toBe/toEqual`.

Test runner: `vitest.workspace.ts` (lines 57–70) puts
`packages/**/*.{test,spec}.{ts,js}` in the `@calcom/lib` project under node with
`packages/testing/src/setupVitest.ts`; only `packages/lib/hooks/**` is excluded, so
the two new files are picked up without config changes. No timezone dependence.

Verify: `yarn test packages/lib/convertToNewDurationType.test.ts packages/lib/findDurationType.test.ts`.

## Edge Cases

- `Math.ceil` rounds non-even conversions **up** (90 min → 2 h, 1441 min → 2 d,
  25 h → 2 d). Asserted as-is; flagged in the PR description as possibly surprising.
- `findDurationType(0)` returns `"days"` because `0 % 1440 === 0`. Asserted as-is;
  flagged in the PR description.
- `Math.ceil(0)` is `0` for every pair (no `-0` issue: `Math.ceil(0 / 60)` is `0`,
  and `toBe(0)` uses `Object.is`, which distinguishes `-0` — non-negative inputs
  never produce `-0` here).

## Out of Scope

- Changing either function, including the `Math.ceil` rounding or the `0 → "days"`
  result (issue #11 Constraints: "Tests only").
- Negative or non-integer inputs — the issue does not ask for them.
- Tests for `EventLimitsTab.tsx`.
- Size rule from `specs/README.md` (lines 77–79: max 5–7 files excluding tests, max
  500 lines): this is two test files plus the spec, well inside one PR.
