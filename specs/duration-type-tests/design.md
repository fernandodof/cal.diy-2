# Duration Type Tests Design

## Overview

Add unit tests for two pure helpers in `packages/lib/`: `convertToNewDurationType`,
which converts a value between `minutes` / `hours` / `days` and rounds the result
up with `Math.ceil`, and `findDurationType`, which picks the coarsest unit that
divides a minute value evenly. Tests only — neither function changes.

Source: [issue #11](https://github.com/fernandodof/cal.diy-2/issues/11).

## Problem Statement

Both functions have no test coverage (no `*uration*.test.ts` exists in
`packages/lib/`). They back the duration pickers in
`packages/features/eventtypes/components/tabs/limits/EventLimitsTab.tsx`
(lines 12–14, 334–345), so a regression in either would silently change the
values shown and saved in event-type limits.

## User Stories

- As a maintainer, I want the current behaviour of the duration helpers pinned
  by tests so that a refactor cannot change it unnoticed.

## Acceptance Criteria

- [ ] Identity pairs (`minutes_minutes`, `hours_hours`, `days_days`) return the value unchanged — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should return the value unchanged for identity conversions
- [ ] minutes → hours converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should convert minutes to hours
- [ ] minutes → days converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should convert minutes to days
- [ ] hours → minutes converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should convert hours to minutes
- [ ] hours → days converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should convert hours to days
- [ ] days → minutes converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should convert days to minutes
- [ ] days → hours converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should convert days to hours
- [ ] Lossy minutes → hours rounds up (90 → 2) — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should round up minutes to hours when not evenly divisible
- [ ] Lossy minutes → days rounds up (1441 → 2) — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should round up minutes to days when not evenly divisible
- [ ] Lossy hours → days rounds up (25 → 2) — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should round up hours to days when not evenly divisible
- [ ] Zero input returns 0 for all nine pairs — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType should return 0 for a zero value in every direction
- [ ] A value divisible by 1440 returns `"days"` — `packages/lib/findDurationType.test.ts` › findDurationType should return days for a value divisible by 1440
- [ ] A value divisible by 60 but not 1440 returns `"hours"` — `packages/lib/findDurationType.test.ts` › findDurationType should return hours for a value divisible by 60 but not 1440
- [ ] Anything else returns `"minutes"` — `packages/lib/findDurationType.test.ts` › findDurationType should return minutes for a value not divisible by 60
- [ ] `0` returns `"days"` (current behaviour, asserted not changed) — `packages/lib/findDurationType.test.ts` › findDurationType should return days for 0

## Technical Design

### Database Changes

None.

### API Changes

None.

### UI Changes

None.

### Files

| File | Change |
|---|---|
| `packages/lib/convertToNewDurationType.test.ts` | New. One `describe("convertToNewDurationType")`. |
| `packages/lib/findDurationType.test.ts` | New. One `describe("findDurationType")`. |

Code under test (read, not modified):

- `packages/lib/convertToNewDurationType.ts` — default export
  `convertToNewDurationType(prevType, newType, prevValue)`; also exports
  `MINUTES_IN_HOUR = 60`, `MINUTES_IN_DAY = 1440`, `HOURS_IN_DAY = 24` and the
  `DurationType` type. The constants live in this file, not in
  `packages/lib/constants.ts`. Looks up `${prevType}_${newType}` in a map of nine
  functions and returns `Math.ceil` of the result.
- `packages/lib/findDurationType.ts` — default export `findDurationType(value)`;
  checks `value % MINUTES_IN_DAY === 0` first, then `% MINUTES_IN_HOUR`, else
  `"minutes"`.

Conventions, from `packages/lib/array.test.ts`: `import { describe, it, expect }
from "vitest"`, a blank line, then the import of the code under test; one
`describe` per function; `it("should …")` titles. Both helpers are default
exports, so the tests import them as defaults.

Test runner: `packages/lib/*.test.ts` falls under the `@calcom/lib` node project
in `vitest.workspace.ts` (include `packages/**/*.{test,spec}.{ts,js}`, lines
59–70); `packages/lib/hooks/**` is the only `packages/lib` exclusion. `yarn test`
is `TZ=UTC vitest run` (`package.json:78`); nothing here is timezone-sensitive.

## Edge Cases

- `Math.ceil` rounds lossy conversions up (90 min → 2 h, 1441 min → 2 days,
  25 h → 2 days). Asserted as-is; flagged in the PR description as possibly
  surprising, not fixed.
- `findDurationType(0)` returns `"days"` because `0 % 1440 === 0`. Asserted
  as-is; flagged in the PR description.
- Zero through `convertToNewDurationType` returns `0` in all directions
  (`Math.ceil(0) === 0`).
- Negative values, `NaN`, and invalid `DurationType` strings are not in the issue
  and are not covered.

## Out of Scope

- Any change to `convertToNewDurationType.ts` or `findDurationType.ts` — the issue
  says tests only.
- Tests for `EventLimitsTab.tsx`, the caller.
- `specs/README.md` review-size rule (max 5–7 non-test files, 500 lines): this
  change is two test files plus this spec, well inside one PR.
