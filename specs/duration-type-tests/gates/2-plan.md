Outcome: continue

# Phase 2 — Plan gate

Spec: `specs/duration-type-tests/`
Base branch: `main`

## Slices

1. **`findDurationType` is pinned** — `packages/lib/findDurationType.test.ts`
   (new). Days / hours / minutes branches plus `0 → "days"`.
   Verified by `yarn test packages/lib/findDurationType.test.ts`.
2. **`convertToNewDurationType` exact conversions** —
   `packages/lib/convertToNewDurationType.test.ts` (new). Identity pairs and the
   six cross-unit directions with evenly divisible values.
   Verified by `yarn test packages/lib/convertToNewDurationType.test.ts`.
3. **`convertToNewDurationType` rounding and zero** — same file. `Math.ceil`
   round-up for the three lossy directions (ADR-001) and `0` in all nine pairs.
   Verified by `yarn test packages/lib/convertToNewDurationType.test.ts`.

All 15 acceptance criteria in `design.md` map to a test title in exactly one
slice. Both design files appear in a slice; no source files change. One PR.
