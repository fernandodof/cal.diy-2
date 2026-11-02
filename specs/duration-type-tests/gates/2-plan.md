Outcome: continue

# Gate 2 — Plan

Spec: `specs/duration-type-tests/`
Base branch: `main`

## Slices

1. **`findDurationType` is pinned** — `packages/lib/findDurationType.test.ts` (new).
   Covers days for a value divisible by 1440, hours for divisible by 60 but not 1440,
   minutes otherwise, days for 0.
   Verified by: `yarn test packages/lib/findDurationType.test.ts`
2. **`convertToNewDurationType` exact conversions are pinned** —
   `packages/lib/convertToNewDurationType.test.ts` (new). Covers the three identity
   pairs and the six cross-unit conversions on values that divide evenly.
   Verified by: `yarn test packages/lib/convertToNewDurationType.test.ts`
3. **`convertToNewDurationType` rounding and zero are pinned** — same file. Covers
   `Math.ceil` rounding up (90 min → 2 h, 1441 min → 2 d, 25 h → 2 d) and 0 → 0 in
   all nine directions.
   Verified by: `yarn test packages/lib/convertToNewDurationType.test.ts`

Size: two test files, no source changes. One PR.
