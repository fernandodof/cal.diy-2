# Duration Type Tests Design

## Overview

Adds unit tests for two pure helpers in `packages/lib/`: `convertToNewDurationType`,
which converts a value between `minutes` / `hours` / `days`, and `findDurationType`,
which picks the coarsest unit that divides a minute value evenly. Tests only — neither
function's behaviour changes.

## Problem Statement

Both functions have no test coverage (no `*DurationType*.test.ts` exists in
`packages/lib/`). They feed the event-type limits UI
(`packages/features/eventtypes/components/tabs/limits/EventLimitsTab.tsx` is the only
caller outside `packages/lib/`), so a regression in rounding or unit selection would
silently change the durations users see. Source: issue #11.

## User Stories

- As a maintainer, I want the duration helpers covered by tests so that a change to
  their rounding or unit selection is caught in CI.

## Acceptance Criteria

- [ ] `minutes_minutes` returns the value unchanged — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType returns the value unchanged for minutes to minutes
- [ ] `hours_hours` returns the value unchanged — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType returns the value unchanged for hours to hours
- [ ] `days_days` returns the value unchanged — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType returns the value unchanged for days to days
- [ ] minutes → hours converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts minutes to hours
- [ ] minutes → days converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts minutes to days
- [ ] hours → minutes converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts hours to minutes
- [ ] hours → days converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts hours to days
- [ ] days → minutes converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts days to minutes
- [ ] days → hours converts — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType converts days to hours
- [ ] minutes → hours rounds up when not evenly divisible (90 → 2) — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType rounds minutes to hours up when not evenly divisible
- [ ] minutes → days rounds up when not evenly divisible (1500 → 2) — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType rounds minutes to days up when not evenly divisible
- [ ] hours → days rounds up when not evenly divisible (25 → 2) — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType rounds hours to days up when not evenly divisible
- [ ] zero input returns 0 for every pair — `packages/lib/convertToNewDurationType.test.ts` › convertToNewDurationType returns 0 for a zero value in every direction
- [ ] a value divisible by 1440 returns `"days"` — `packages/lib/findDurationType.test.ts` › findDurationType returns days for a value divisible by 1440
- [ ] a value divisible by 60 but not 1440 returns `"hours"` — `packages/lib/findDurationType.test.ts` › findDurationType returns hours for a value divisible by 60 but not 1440
- [ ] any other value returns `"minutes"` — `packages/lib/findDurationType.test.ts` › findDurationType returns minutes for a value not divisible by 60
- [ ] `0` returns `"days"` (current behaviour) — `packages/lib/findDurationType.test.ts` › findDurationType returns days for 0

## Technical Design

### Database Changes

None.

### API Changes

None.

### UI Changes

None.

### Files

Read, not changed:

- `packages/lib/convertToNewDurationType.ts` — exports `MINUTES_IN_HOUR = 60`,
  `MINUTES_IN_DAY = 1440`, `HOURS_IN_DAY = 24`, `DurationType`, and the default
  export. Looks up `${prevType}_${newType}` in a map of nine closures and returns
  `Math.ceil` of the result.
- `packages/lib/findDurationType.ts` — default export; `value % MINUTES_IN_DAY === 0`
  → `"days"`, else `value % MINUTES_IN_HOUR === 0` → `"hours"`, else `"minutes"`.

Added:

- `packages/lib/convertToNewDurationType.test.ts`
- `packages/lib/findDurationType.test.ts`

Conventions, from `packages/lib/array.test.ts`: `import { describe, it, expect } from "vitest"`,
a blank line, then the relative import of the module under test; one `describe` per
function; plain `it` blocks with lowercase present-tense titles. Use plain `it` rather
than `it.each`, so each test's full name matches the acceptance criteria exactly.

Both files run in the `@calcom/lib` node project of `vitest.workspace.ts`
(`packages/**/*.{test,spec}.{ts,js}`; `packages/lib/hooks/**` is excluded, the root
of `packages/lib/` is not). `yarn test` is `TZ=UTC vitest run` (`package.json`);
nothing here is timezone-sensitive.

## Edge Cases

- `Math.ceil` makes lossy conversions round up (90 min → 2 h). Asserted as-is.
- `findDurationType(0)` returns `"days"` because 0 is divisible by 1440. Asserted as-is.
- Both look like possible bugs; per the issue, they go in the PR description, not a fix.

## Out of Scope

- Any change to either function's behaviour (issue constraint: tests only).
- Non-integer, negative, or invalid-unit inputs — the issue does not ask for them.
- The `EventLimitsTab.tsx` caller.
- Size: two test files, well inside the `specs/README.md` limit of 5-7 non-test files
  and 500 lines per PR — one PR.
