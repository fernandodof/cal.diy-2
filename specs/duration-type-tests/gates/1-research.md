Outcome: continue

# Phase 1 — Research gate

Spec: `specs/duration-type-tests/`

## Overview

Add unit tests for two pure helpers in `packages/lib/`: `convertToNewDurationType`,
which converts a value between `minutes` / `hours` / `days` and rounds the result
up with `Math.ceil`, and `findDurationType`, which picks the coarsest unit that
divides a minute value evenly. Tests only — neither function changes.

## Files

New:

- `packages/lib/convertToNewDurationType.test.ts`
- `packages/lib/findDurationType.test.ts`

Read, not modified:

- `packages/lib/convertToNewDurationType.ts` (also defines the `MINUTES_IN_HOUR`,
  `MINUTES_IN_DAY`, `HOURS_IN_DAY` constants)
- `packages/lib/findDurationType.ts`
- `packages/lib/array.test.ts` (convention reference)
- `vitest.workspace.ts` (confirms `packages/lib/*.test.ts` runs in the `@calcom/lib` node project)

## Open questions and assumptions

1. **Is `Math.ceil` rounding, or `findDurationType(0) === "days"`, a bug?**
   Assumption: per the issue, assert today's behaviour and flag both in the PR
   description (recorded as ADR-001 in `decisions.md`).
2. **Negative values / `NaN` / invalid unit strings?** Not requested by the
   issue. Assumption: not covered; noted in `future-work.md`.
3. **Which values exercise each direction?** Assumption: exact cases use 2 of
   the target unit (120 min, 2880 min, 2 h, 48 h, 2 days); lossy cases are
   90 min → 2 h, 1441 min → 2 days, 25 h → 2 days.
