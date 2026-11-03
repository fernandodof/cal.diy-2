Outcome: continue

Base branch: `main`

## Slices

1. **`truncateOnWord` cuts within `maxLength` on the last space** — replaces the
   hard-coded 148 with `maxLength - 3` (ellipsis) or `maxLength`, then backs off
   to the last space.
   - `packages/lib/text.ts`, `packages/lib/text.test.ts`
   - Tests: original text when shorter; cut on last space; cut on last space
     without ellipsis; long text at most 158 on a word boundary
   - Verified by: `yarn test packages/lib/text.test.ts`
2. **Hard cut when the cut part has no space** — backs off only when
   `lastIndexOf(" ") > 0`, so `"x".repeat(200)` at 20 gives 17 `x` + `"..."`.
   - `packages/lib/text.ts`, `packages/lib/text.test.ts`
   - Test: should hard cut the text when the cut part has no space
   - Verified by: `yarn test packages/lib/text.test.ts`

One PR: 1 non-test file, within the review-size rule.
