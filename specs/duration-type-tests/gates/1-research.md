Outcome: continue

## Overview

Adds unit tests for two pure helpers in `packages/lib/`: `convertToNewDurationType`,
which converts a value between `minutes` / `hours` / `days`, and `findDurationType`,
which picks the coarsest unit that divides a minute value evenly. Tests only — neither
function's behaviour changes.

## Files

Read, not changed:

- `packages/lib/convertToNewDurationType.ts`
- `packages/lib/findDurationType.ts`

Added:

- `packages/lib/convertToNewDurationType.test.ts`
- `packages/lib/findDurationType.test.ts`

## Open questions and assumptions

- **Plain `it` or `it.each`?** Assumed plain `it`, so each test name is fixed and
  matches the acceptance criteria exactly.
- **What counts as "zero as an input value"?** Assumed one test asserting `0` → `0`
  for all nine pairs.
- **Should the round-up cases use specific values?** Assumed 90 min → 2 h,
  1500 min → 2 d, 25 h → 2 d.
- **Non-integer, negative, or invalid-unit inputs?** Assumed out of scope; the issue
  does not ask for them.
