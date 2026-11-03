Outcome: continue

# Fix round gate

Fixed only the spec findings of kind `missing` or `wrong` from
`.agent-handoff/review.json`. The creep and standards findings were left as they are.

## 1. wrong: a whole word that fits is dropped when the next character is a space

> `truncateOnWord("The quick brown fox jumps", 19, false)` returns `"The quick brown"`.

- `packages/lib/text.ts`: back off to the last space only when
  `text[cutLength] !== " "`. When the cut already ends on a word, it is kept.
- `packages/lib/text.test.ts`: added `("The quick brown fox jumps", 22)` →
  `"The quick brown fox..."` to the "cut on the last space" test, and
  `("The quick brown fox jumps", 19, false)` → `"The quick brown fox"` to the
  "without ellipsis" test.
- `design.md`: the algorithm step, the Edge Cases entry and a new "Whole last
  word" acceptance criterion. The issue's own expected outputs are unchanged.

## 2. missing: `maxLength < 3` with the ellipsis on returns `"..."`, which is longer than `maxLength`

- `packages/lib/text.ts`: `withEllipsis = ellipsis && maxLength >= 3`. When the
  ellipsis does not fit, it is dropped and the text is hard cut to `maxLength`.
- `packages/lib/text.test.ts`: new test "should hard cut the text without
  ellipsis when the max length is too short for it" (`("Hello world", 2)` →
  `"He"`, `("Hello world", 0)` → `""`).
- `design.md`: the algorithm step, the Edge Cases entry and a new "Too short for
  the ellipsis" acceptance criterion.

## 3. missing: the `ellipsis = false` no-space path has no test

- `packages/lib/text.test.ts`: added `("x".repeat(200), 20, false)` →
  20 `x` to "should hard cut the text when the cut part has no space". The loop
  now passes `ellipsis`.
- `design.md`: the "No space" acceptance criterion mentions the case.

## 4. missing: the long-text test expects `input.slice(0, 148)` and never gets close to 158

- `packages/lib/text.test.ts`: the input is now `"Hello "` followed by the
  sentence repeated 5 times. The expected value is written out explicitly, a
  157-character result, and the test asserts `result.length` is 157.
- `design.md`: the "Long text" acceptance criterion mentions the 157 result.

## Checks

- `yarn test packages/lib/text.test.ts`: 9 passed, 1 file.
- `yarn biome check packages/lib/text.ts packages/lib/text.test.ts`: no errors,
  4 infos (nursery `noTernary` / explicit return type, the same style as the
  existing `truncate`).
- The `## Verification` block is unchanged. It still covers the same single
  test file.
