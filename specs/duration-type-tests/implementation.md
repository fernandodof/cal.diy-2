# Duration Type Tests Implementation

## Status: planned

## Completed

## In Progress

## Blocked

## Next Steps

1. **`findDurationType` is pinned** — proves the new `packages/lib/*.test.ts` file is
   picked up by the `@calcom/lib` vitest project and the default-import pattern works
   - `packages/lib/findDurationType.test.ts` (new); reads `packages/lib/findDurationType.ts`
   - Tests: the four `findDurationType …` criteria in design.md — days for a value
     divisible by 1440, hours for divisible by 60 but not 1440, minutes otherwise,
     days for 0
   - Verified by: `yarn test packages/lib/findDurationType.test.ts`
2. **`convertToNewDurationType` exact conversions are pinned** — proves all nine
   `prevType_newType` map entries on values that divide evenly
   - `packages/lib/convertToNewDurationType.test.ts` (new); reads `packages/lib/convertToNewDurationType.ts`
   - Tests: the three "returns the value unchanged when converting X to X" criteria
     and the six "converts X to Y" criteria in design.md
   - Verified by: `yarn test packages/lib/convertToNewDurationType.test.ts`
3. **`convertToNewDurationType` rounding and zero are pinned** — proves the
   `Math.ceil` behaviour as it is today
   - `packages/lib/convertToNewDurationType.test.ts`
   - Tests: the three "rounds up when … do not divide evenly …" criteria (90 min → 2 h,
     1441 min → 2 d, 25 h → 2 d) and "returns 0 for a zero value in every direction"
     (all nine pairs)
   - Verified by: `yarn test packages/lib/convertToNewDurationType.test.ts`

`it` titles must match the Acceptance Criteria in design.md exactly — the harness
looks tests up by full name (`<describe> <it>`).

Size: two new test files plus the spec folder, no source changes — inside the
`specs/README.md` review-size rule (5–7 files excluding tests, 500 lines). One PR.

## Verification

```sh
yarn test packages/lib/findDurationType.test.ts
yarn test packages/lib/convertToNewDurationType.test.ts
```

## Session Notes

- Base branch: `main` (from `--base main`, headless Phase 2). Working branch
  `agent/issue-11` was created by the harness.
- No approach choice was needed in planning, so no new ADR in `decisions.md`.
