Outcome: continue

## Slices

1. **`findDurationType` is covered** — `packages/lib/findDurationType.test.ts` (new);
   days / hours / minutes selection and `0` → `"days"`.
   Verified by `yarn test packages/lib/findDurationType.test.ts`.
2. **`convertToNewDurationType` converts exactly between every unit pair** —
   `packages/lib/convertToNewDurationType.test.ts` (new); three identity pairs and
   six conversions.
   Verified by `yarn test packages/lib/convertToNewDurationType.test.ts`.
3. **`convertToNewDurationType` rounding and zero, as they are today** — same file;
   `Math.ceil` on minutes→hours, minutes→days, hours→days, and `0` in every direction.
   Verified by `yarn test packages/lib/convertToNewDurationType.test.ts`.

Two test files, no source changes — one PR.

## Base branch

`main`
