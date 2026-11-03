# truncateOnWord respects maxLength Design

## Overview

`truncateOnWord(text, maxLength, ellipsis = true)` in `packages/lib/text.ts`
ignores `maxLength` (it always cuts at a hard-coded 148 characters) and returns
just `"..."` when the cut part has no space. Fix it so it behaves like its
neighbour `truncate` — the result, ellipsis included, never exceeds `maxLength`
— but backs off to the last space, falling back to a hard cut when there is none.

## Problem Statement

`packages/lib/text.ts:11` cuts with `text.substring(0, 148)` regardless of
`maxLength`, so `truncateOnWord("The quick brown fox jumps over the lazy dog", 20)`
returns a 42-character string. Line 15 then takes
`substring(0, Math.min(len, lastIndexOf(" ")))`; with no space, `lastIndexOf`
is `-1` and the result is `""`, so `truncateOnWord("x".repeat(200), 20)` returns
`"..."`.

The only callers are `apps/web/app/_utils.tsx:43` and `:101`, which pass `158`
for Open Graph descriptions; today those are cut at ~148 characters instead of
158 (after the fix they may be up to 158 including the ellipsis).

## User Stories

- As a developer calling `truncateOnWord`, I want the result to fit in
  `maxLength` so that I can rely on the limit I pass.
- As a visitor sharing a Cal.com page, I want the preview description to use the
  full allowed length and never collapse to `"..."`.

## Acceptance Criteria

- [ ] Text no longer than `maxLength` is returned unchanged — `packages/lib/text.test.ts` › Text util tests fn: truncateOnWord should return the original text when it is shorter than the max length
- [ ] Short limit: `truncateOnWord("The quick brown fox jumps over the lazy dog", 20)` returns `"The quick brown..."` — `packages/lib/text.test.ts` › Text util tests fn: truncateOnWord should return the text cut on the last space when it is longer than the max length
- [ ] No ellipsis: with `ellipsis = false` the same call returns `"The quick brown fox"` — `packages/lib/text.test.ts` › Text util tests fn: truncateOnWord should return the text cut on the last space without ellipsis when ellipsis is false
- [ ] Whole last word: when the cut ends right before a space, the last word is kept — `truncateOnWord("The quick brown fox jumps", 22)` returns `"The quick brown fox..."` and with `ellipsis = false`, `maxLength` 19 returns `"The quick brown fox"` — `packages/lib/text.test.ts` › Text util tests fn: truncateOnWord should return the text cut on the last space when it is longer than the max length, and › Text util tests fn: truncateOnWord should return the text cut on the last space without ellipsis when ellipsis is false
- [ ] Long text: a long text with `maxLength` 158 returns at most 158 characters (157 for the test input, not the old 148-character cut), cut on a word boundary — `packages/lib/text.test.ts` › Text util tests fn: truncateOnWord should cut a long text to at most 158 characters on a word boundary
- [ ] No space: `truncateOnWord("x".repeat(200), 20)` returns `"xxxxxxxxxxxxxxxxx..."` (17 `x` + `...`), and 20 `x` with `ellipsis = false`, a hard cut like `truncate` — `packages/lib/text.test.ts` › Text util tests fn: truncateOnWord should hard cut the text when the cut part has no space
- [ ] Too short for the ellipsis: with `maxLength < 3` the ellipsis is dropped and the text hard cut, so `truncateOnWord("Hello world", 2)` returns `"He"` — `packages/lib/text.test.ts` › Text util tests fn: truncateOnWord should hard cut the text without ellipsis when the max length is too short for it
- [ ] Length: a truncated result, including `"..."`, is never longer than `maxLength` — proven by every case above whose expected value is ≤ `maxLength`, and asserted explicitly in `packages/lib/text.test.ts` › Text util tests fn: truncateOnWord should cut a long text to at most 158 characters on a word boundary

## Technical Design

### Database Changes

None.

### API Changes

None. The signature `truncateOnWord(text: string, maxLength: number, ellipsis = true)`
is unchanged.

Algorithm (mirrors `truncate` at `packages/lib/text.ts:1-5`):

1. If `text.length <= maxLength`, return `text`.
2. Cut to `maxLength - 3` characters when `ellipsis` is true and
   `maxLength >= 3`, otherwise `maxLength` (the ellipsis is dropped when it
   does not fit).
3. If the next character of the original text is a space, the cut already ends
   on a word: keep it. Otherwise take `lastIndexOf(" ")` in the cut part; if it
   is `> 0`, cut there, else keep the hard cut.
4. Append `"..."` when the ellipsis is kept.

### UI Changes

None directly. Open Graph descriptions built in `apps/web/app/_utils.tsx`
become up to 158 characters instead of ~148.

### Files

Modified:

- `packages/lib/text.ts` — rewrite `truncateOnWord` (lines 7–20)
- `packages/lib/text.test.ts` — import `truncateOnWord`; add
  `describe("fn: truncateOnWord")` inside `describe("Text util tests")`, after
  the `truncate` block, using the same `cases` array style (`input`,
  `maxLength`, optional `ellipsis`, `expected`)

Read, not modified:

- `apps/web/app/_utils.tsx` (the only callers, lines 11, 43, 101)
- `specs/README.md` (review-size rule — this is 1 non-test file, one PR)

## Edge Cases

- Text exactly `maxLength` long: returned unchanged.
- Cut part has no space (or only a leading space at index 0): hard cut, never
  an empty string before the ellipsis.
- Cut part ends right before a space in the original text: the last word is
  complete, so the cut is kept rather than backing off and dropping it (changed
  in the fix round after review; the issue's expected outputs are unaffected).
- `maxLength < 3` with ellipsis: the ellipsis cannot fit, so it is dropped and
  the text hard cut to `maxLength` (changed in the fix round after review, to
  keep the "never longer than `maxLength`" guarantee).

## Out of Scope

- Changing `truncate` or the callers in `apps/web/app/_utils.tsx` (issue
  constraint).
- Trimming trailing punctuation or whitespace before the ellipsis.
- Using a Unicode ellipsis character or any other word-boundary definition than
  a plain space.
