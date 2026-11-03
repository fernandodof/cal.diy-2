Outcome: continue

# Phase 1 — Research gate

Spec: `specs/truncate-on-word-max-length/`

## Overview

`truncateOnWord(text, maxLength, ellipsis = true)` in `packages/lib/text.ts`
ignores `maxLength` (it always cuts at a hard-coded 148 characters, line 11) and
returns just `"..."` when the cut part has no space (`lastIndexOf(" ")` is `-1`,
line 15). Fix it so it behaves like its neighbour `truncate` — the result,
ellipsis included, never exceeds `maxLength` — but backs off to the last space,
falling back to a hard cut when there is none.

## Files

Modified:

- `packages/lib/text.ts` — rewrite `truncateOnWord` (lines 7–20)
- `packages/lib/text.test.ts` — import `truncateOnWord`; new
  `describe("fn: truncateOnWord")` block after the `truncate` block

Read, not modified:

- `apps/web/app/_utils.tsx` (the only callers, lines 11, 43, 101 — pass `158`)
- `specs/README.md` (review-size rule: 1 non-test file, one PR)

## Open questions and assumptions

1. **Cut ends right before a space.** If the character after the cut is a space,
   the whole last word in the cut part is a complete word, yet "back to the last
   space" drops it. **Assumption:** follow the issue literally (cut, then back
   to the last space inside the cut part); the issue's expected outputs —
   `"The quick brown..."` and `"The quick brown fox"` — are consistent with this.
2. **Space at index 0 only.** Cutting there would leave an empty string.
   **Assumption:** treat `lastIndexOf(" ") <= 0` as "no space" and hard cut.
3. **`maxLength < 3` with ellipsis.** Not specified. **Assumption:** behave as
   `truncate` does; no new handling, no test, since no caller passes such a value.
