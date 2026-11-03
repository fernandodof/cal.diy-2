Outcome: continue

Review of `git diff origin/main...HEAD` (5 commits, #63). Spec: `design.md` + issue #63.
Standards: `CONTRIBUTING.md`, root `CLAUDE.md`, and the smell baseline.

## Standards

I found **no hard violations**. CONTRIBUTING.md and CLAUDE.md say nothing about this kind of code, beyond matching the surrounding idioms and keeping PRs small. This PR is about 110 lines of code across 2 code files, well inside the limits of 500 lines and 10 files. Everything below is a judgement call.

**packages/lib/text.ts**

1. **Magic number for the ellipsis (Primitive Obsession / Duplicated Code), text.ts:11 and :18.** The code does `text.substring(0, ellipsis ? maxLength - 3 : maxLength)` and later `truncatedText += "..."`. `truncate` (line 4) already has the same `maxLength - 3` / `"..."` pair, so the ellipsis length is now hard-coded in two functions. The obvious fix is a module constant such as `const ELLIPSIS = "..."` and `ELLIPSIS.length`. That said, upstream already has the bare `3` and the change follows the existing style, so leaving it is defensible.
2. **The two functions now behave differently when `ellipsis` is false, text.ts:11.** `truncateOnWord` uses the full `maxLength`, but `truncate` still subtracts 3 (`text.slice(0, maxLength - 3)`). That is arguably the correct behaviour, but the spec's CLAUDE.md says to "Mirror `truncate`", so a reviewer may ask. Worth one line in the PR description.
3. **Naming and comment density are fine.** `lastSpaceIndex` says what it holds, and the added comment matches the existing comment's tone.

**packages/lib/text.test.ts**

4. **Import blank line removed, text.test.ts:1-2.** The diff deletes the blank line between the `vitest` import and the `./text` import, which the original file had. `packages/lib` tests are mixed: `array.test.ts` and `crypto.test.ts` keep the blank line, `convertToNewDurationType.test.ts` doesn't. It's an unneeded diff line, not a breach. (If biome made this change, ignore it.)
5. **Repeated test loop (Duplicated Code), text.test.ts:87, 108, 132, 161.** The `for (const {…} of cases) { const result = …; expect(...) }` shape appears four more times. The existing `truncate` tests (lines 20, 41, 64) use the same pattern, and the spec says to use it. Matching the repo wins, so this is not worth changing.
6. **One-element `cases` array (Speculative Generality), text.test.ts:153-159.** "should hard cut…" loops over an array with only one case. It's harmless, but either add a second case (for example `ellipsis: false`) or write the assertion directly.
7. **Mysterious literal and redundant assertions, text.test.ts:140-150.** `expect(result).toEqual(`${input.slice(0, 148)}...`)` brings back the old hard-coded `148` with no explanation. Because it's an exact-equality check, the three assertions after it (length, `startsWith`, the next character being a space) can never fail on their own. Either keep the exact check and drop the other three, or keep the property checks and drop the literal. The "158" in the test name is also unexplained; a short comment naming the SEO caller in `apps/web/app/_utils.tsx` would fix that.

**specs/**

8. **No convention breaches.** The folder follows the existing `specs/<slug>/` layout (CLAUDE.md, design.md, gates/, and so on) used by the sibling spec folders.

## Spec

I found no hard requirement breaches. The fix in `packages/lib/text.ts:10-18` follows the issue, and `yarn test packages/lib/text.test.ts` passes (8/8). I worked each acceptance example through the code:

- **Short limit:** the cut is `"The quick brown f"`, the last space is at index 15, so the result is `"The quick brown..."` (18 characters).
- **No ellipsis:** the cut is `"The quick brown fox "`, the last space is at index 19, so the result is `"The quick brown fox"`.
- **No space:** `lastSpaceIndex` is -1, so the hard cut stays and the result is 17 `x` plus `...`. With `ellipsis=false` it is a hard cut to exactly `maxLength`.
- **Length with `ellipsis=false`:** the result is at most `maxLength` in every case.
- **Long text:** 275 characters are cut to 155, the last space is at 148, so the result is 151 characters. The old code would have backed off to 136, so the test does tell old from new.

**(a) Missing or partial**
1. Spec: "a truncated result, including the "...", is never longer than `maxLength`." For `maxLength < 3` with the ellipsis on, `text.ts:11` takes `substring(0, negative)`, which gives `""`, then adds `"..."`, so the result is 3 characters. The spec's Edge Cases section knowingly leaves this out ("behaves as `truncate` does"). Judgement call: no caller passes such a value.
2. Spec: "No space: … the result is a hard cut." This is tested only with the ellipsis on (`text.test.ts:152-167`); the `ellipsis=false` no-space path has no test. Judgement call, minor.
3. Spec: "Long text: … returns at most 158 characters, cut on a word boundary." The test asserts both, through `input[cutText.length] === " "`. But its expected value is written as `input.slice(0, 148)` (`text.test.ts:146`), the same number as the removed hard-coded 148. It is correct, but it reads like the old bug. The 151-character result also never gets close to 158, so this test does not exercise the upper limit. Judgement call.

**(b) Scope creep**
- `text.test.ts:2` removes the blank line between the vitest import and the local import. This is probably biome's import ordering. Judgement call, harmless.
- Otherwise, `truncate`, the signature and `apps/web/app/_utils.tsx` are untouched. The extra test cases (`"Hello world"` at 10 and 11) are in scope.

**(c) Implemented but looks wrong**
- The space at the cut boundary, which you asked about. `truncateOnWord("The quick brown fox jumps", 19, false)` cuts to `"The quick brown fox"` and then backs off to `"The quick brown"`, even though the next character in the original is a space and `"The quick brown fox"` would fit. The issue's wording, "cut to `maxLength` … then back to the last space", allows this, and the spec's Edge Cases section says it is intended. It does drop a whole word that fits. Judgement call, not a breach. Checking for a space at `text[cutLength]` would avoid it, but nothing in the issue requires that.
- `lastSpaceIndex > 0` (`text.ts:16`) treats a lone leading space as "no space" and keeps the hard cut. That matches the spec's Edge Cases section and is correct.

---

**Summary:** Standards has 0 hard violations and 5 judgement findings (items 1, 2, 4, 6, 7; items 3, 5 and 8 need no action). The worst is item 7: the long-text test hard-codes `148` and has redundant assertions. Spec has 0 hard breaches and 5 judgement findings. The worst is the boundary-space behaviour, which drops a word that fits but is allowed by the issue's wording and is documented as intended.
