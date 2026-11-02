Outcome: continue

# Gate 1 — Research

Spec: `specs/duration-type-tests/`

## Overview

Add unit tests for two pure helpers in `packages/lib/`:
`convertToNewDurationType` (convert a value between `minutes` / `hours` / `days`,
rounding up with `Math.ceil`) and `findDurationType` (pick the coarsest unit that
divides a minute value evenly). Tests only — neither function's behaviour changes.

## Files

Read (unchanged):

- `packages/lib/convertToNewDurationType.ts`
- `packages/lib/findDurationType.ts`

Added:

- `packages/lib/convertToNewDurationType.test.ts`
- `packages/lib/findDurationType.test.ts`

Convention reference: `packages/lib/array.test.ts`. Runner config:
`vitest.workspace.ts` lines 57–70 (`@calcom/lib` project, node) already includes
`packages/**/*.test.ts`, so no config change.

## Open questions and assumptions

- **Test granularity for "all nine pairs".** Assumed one `it` per pair (three
  identity, six conversions) so each acceptance criterion maps to one named test.
- **Zero input.** Assumed a single `it` that loops over all nine pairs and asserts
  `0`, rather than nine more tests.
- **Rounding cases.** Assumed 90 min → hours (`2`), 1441 min → days (`2`), and
  25 h → days (`2`) as the uneven examples for the three lossy directions.
- **Negative / fractional inputs.** Not covered — the issue does not ask for them.
