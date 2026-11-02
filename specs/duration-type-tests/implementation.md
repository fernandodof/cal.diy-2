# Duration Type Tests Implementation

## Status: planned

## Completed

## In Progress

## Blocked

## Next Steps

1. **`findDurationType` is covered** — thinnest path: one new test file runs in the
   `@calcom/lib` vitest project and asserts all four unit-selection cases
   - `packages/lib/findDurationType.test.ts` (new)
   - Tests, titled exactly as in design.md's acceptance criteria:
     `returns days for a value divisible by 1440`,
     `returns hours for a value divisible by 60 but not 1440`,
     `returns minutes for a value not divisible by 60`,
     `returns days for 0` (current behaviour, ADR-001)
   - Verified by: `yarn test packages/lib/findDurationType.test.ts`
2. **`convertToNewDurationType` converts exactly between every unit pair** — all
   nine `${prevType}_${newType}` closures, with evenly divisible inputs
   - `packages/lib/convertToNewDurationType.test.ts` (new)
   - Tests: `returns the value unchanged for minutes to minutes` / `hours to hours` /
     `days to days`; `converts minutes to hours`, `converts minutes to days`,
     `converts hours to minutes`, `converts hours to days`, `converts days to minutes`,
     `converts days to hours`
   - Verified by: `yarn test packages/lib/convertToNewDurationType.test.ts`
3. **`convertToNewDurationType` rounding and zero, as they are today** — pins
   `Math.ceil` on the three lossy directions and `0` in all nine directions (ADR-001)
   - `packages/lib/convertToNewDurationType.test.ts`
   - Tests: `rounds minutes to hours up when not evenly divisible` (90 → 2),
     `rounds minutes to days up when not evenly divisible` (1500 → 2),
     `rounds hours to days up when not evenly divisible` (25 → 2),
     `returns 0 for a zero value in every direction`
   - Verified by: `yarn test packages/lib/convertToNewDurationType.test.ts`

Every test sits inside `describe("convertToNewDurationType")` or
`describe("findDurationType")`, so its full name matches the acceptance criterion.
Neither `convertToNewDurationType.ts` nor `findDurationType.ts` changes.

Size: two new test files, no non-test files — inside the `specs/README.md` limit;
one PR.

## Verification

```sh
yarn test packages/lib/findDurationType.test.ts
yarn test packages/lib/convertToNewDurationType.test.ts
```

## Session Notes

- Base branch: `main` (from `--base`). The harness created and checked out
  `agent/issue-11`; no branch was cut in this phase.
- Flag in the PR body: `Math.ceil` rounding up and `findDurationType(0)` → `"days"`
  are asserted as-is, not fixed (ADR-001, `future-work.md`).
