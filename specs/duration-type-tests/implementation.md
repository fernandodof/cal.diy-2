# Duration Type Tests Implementation

## Status: planned

## Completed

## In Progress

## Blocked

## Next Steps

1. **`findDurationType` is pinned** — proves a new `packages/lib/*.test.ts` file
   is picked up by the `@calcom/lib` vitest project and the default-import
   convention works; the thinnest end-to-end path.
   - `packages/lib/findDurationType.test.ts` (new)
   - Tests, titles exactly as in `design.md` › Acceptance Criteria:
     - `findDurationType should return days for a value divisible by 1440` (1440, 2880)
     - `findDurationType should return hours for a value divisible by 60 but not 1440` (60, 120)
     - `findDurationType should return minutes for a value not divisible by 60` (1, 45, 90)
     - `findDurationType should return days for 0`
   - Verified by: `yarn test packages/lib/findDurationType.test.ts`
2. **`convertToNewDurationType` exact conversions** — proves all nine
   `${prevType}_${newType}` map entries are reachable and correct for values
   that divide evenly.
   - `packages/lib/convertToNewDurationType.test.ts` (new)
   - Tests:
     - `convertToNewDurationType should return the value unchanged for identity conversions` (minutes/hours/days with themselves)
     - `convertToNewDurationType should convert minutes to hours` (120 → 2)
     - `convertToNewDurationType should convert minutes to days` (2880 → 2)
     - `convertToNewDurationType should convert hours to minutes` (2 → 120)
     - `convertToNewDurationType should convert hours to days` (48 → 2)
     - `convertToNewDurationType should convert days to minutes` (2 → 2880)
     - `convertToNewDurationType should convert days to hours` (2 → 48)
   - Verified by: `yarn test packages/lib/convertToNewDurationType.test.ts`
3. **`convertToNewDurationType` rounding and zero** — pins the `Math.ceil`
   behaviour recorded in ADR-001 and the zero case in every direction.
   - `packages/lib/convertToNewDurationType.test.ts` (extends slice 2's `describe`)
   - Tests:
     - `convertToNewDurationType should round up minutes to hours when not evenly divisible` (90 → 2)
     - `convertToNewDurationType should round up minutes to days when not evenly divisible` (1441 → 2)
     - `convertToNewDurationType should round up hours to days when not evenly divisible` (25 → 2)
     - `convertToNewDurationType should return 0 for a zero value in every direction` (all nine pairs)
   - Verified by: `yarn test packages/lib/convertToNewDurationType.test.ts`

Size: two new test files, no non-test source files — well inside the
`specs/README.md` review-size rule; one PR.

## Verification

```sh
yarn test packages/lib/findDurationType.test.ts
yarn test packages/lib/convertToNewDurationType.test.ts
```

## Session Notes

- Base branch: `main` (from `--base main`). Working branch `agent/issue-11` was
  created by the harness.
- PR description must flag the `Math.ceil` rounding and
  `findDurationType(0) === "days"` as asserted-as-is (ADR-001).
