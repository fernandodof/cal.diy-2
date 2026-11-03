# truncateOnWord respects maxLength Implementation

## Status: complete

## Completed

1. **`truncateOnWord` cuts within `maxLength` on the last space** — proves the
   limit passed by the caller is honoured, ellipsis included, replacing the
   hard-coded 148
   - `packages/lib/text.ts` — in `truncateOnWord`, cut to `maxLength - 3` when
     `ellipsis` is true (otherwise `maxLength`) instead of `148`, then back off
     to `lastIndexOf(" ")`
   - `packages/lib/text.test.ts` — import `truncateOnWord`; add
     `describe("fn: truncateOnWord")` after the `truncate` block with the
     `cases`-array tests:
     - should return the original text when it is shorter than the max length
     - should return the text cut on the last space when it is longer than the max length
     - should return the text cut on the last space without ellipsis when ellipsis is false
     - should cut a long text to at most 158 characters on a word boundary
   - Verified by: `yarn test packages/lib/text.test.ts`
2. **Hard cut when the cut part has no space** — proves the `"..."`-only
   result is gone, falling back to a `truncate`-style cut
   - `packages/lib/text.ts` — only back off to the last space when
     `lastIndexOf(" ") > 0`; otherwise keep the hard cut
   - `packages/lib/text.test.ts` — add
     "should hard cut the text when the cut part has no space"
     (`"x".repeat(200)`, `20` → 17 `x` + `"..."`)
   - Verified by: `yarn test packages/lib/text.test.ts`

## In Progress

## Blocked

## Next Steps

Size: 1 non-test file, well under the 5-7 file / 500 line rule in
`specs/README.md` — one PR.

## Verification

```sh
yarn test packages/lib/text.test.ts
```

## Session Notes

- Base branch: `main` (given as `--base` to the headless run; the harness
  created and checked out `agent/issue-63`).
- Test names above must match the acceptance criteria in `design.md` exactly;
  the harness looks them up by full name.
- Slice 1 done: `truncateOnWord` cuts to `maxLength - 3` (or `maxLength`
  without ellipsis) instead of 148; the four slice 1 tests pass. The long-text
  test asserts the exact result, so it fails under the old 148 cut. Next:
  slice 2, the hard cut when there is no space.
- Slice 2 done: the cut only backs off to the last space when
  `lastIndexOf(" ") > 0`, so text with no space is hard cut like `truncate`;
  all 8 tests in `packages/lib/text.test.ts` pass. Next: none, the PR.
- Fix round (review spec findings, see `gates/fix.md`): the cut is kept when
  the next character is a space, so a complete last word is no longer dropped;
  with `maxLength < 3` the ellipsis is dropped and the text hard cut; added the
  `ellipsis = false` no-space case and the "should hard cut the text without
  ellipsis when the max length is too short for it" test; the long-text test
  now expects an explicit 157-character result instead of
  `input.slice(0, 148)`. All 9 tests in `packages/lib/text.test.ts` pass. The
  Verification block is unchanged (same test file).
