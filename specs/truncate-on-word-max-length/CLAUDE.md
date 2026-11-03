# CLAUDE.md — truncateOnWord respects maxLength

## Project Context

`truncateOnWord` in `packages/lib/text.ts` ignored `maxLength` (hard-coded 148)
and returned `"..."` for text with no space. Fix it so the result never exceeds
`maxLength`, cuts on the last space, and falls back to a hard cut like
`truncate`. Issue #63.

## Before Starting Work

1. Read specs/truncate-on-word-max-length/design.md
2. Check specs/truncate-on-word-max-length/implementation.md for current progress
3. Look at `truncate` in `packages/lib/text.ts` and its tests in
   `packages/lib/text.test.ts`

## Code Patterns

- Mirror `truncate`: early return when `text.length <= maxLength`, cut to
  `maxLength - 3` with ellipsis, append `"..."`
- Tests live in `packages/lib/text.test.ts`, in `describe("fn: truncateOnWord")`
  inside `describe("Text util tests")`, using `cases` arrays of
  `{ input, maxLength, ellipsis?, expected }` looped with `for … of`
- Verify with `yarn test packages/lib/text.test.ts`

## Don't

- Don't add features not in design.md
- Don't skip tests
- Don't change the signature, `truncate`, or the callers in `apps/web/app/_utils.tsx`
