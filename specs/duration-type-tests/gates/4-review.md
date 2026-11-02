Outcome: blocked

**Blocked:** the review itself is complete (below), but `.claude/headless-runs/review.json`
could not be written — the session's permission settings treat that path as a sensitive
file and denied the write, and a headless run cannot approve it. I did not work around
the denial. The intended contents (4 standards smells, 0 spec findings) are in
`## review.json (not written)` at the end of this file; allow writes to
`.claude/headless-runs/` and re-run Phase 4, or save that block by hand.

Fixed point: `origin/main` (78125465cb). Spec: `specs/duration-type-tests/design.md` + issue #11.
Standards: `CONTRIBUTING.md`, `CLAUDE.md`, plus the code-review smell baseline.

## Standards

I found no hard violations. I compared the two new test files against `CONTRIBUTING.md` and `CLAUDE.md`. `CONTRIBUTING.md` has no testing rules (its "Testing" section only says "coming soon"), and its file-naming rules cover class-based service and repository files, not `*.test.ts`. The PR-size rule ("under 500 lines… under 10 code files") is met: there are 2 code files and about 88 changed code lines, and spec docs don't count toward the limits. Both files match `packages/lib/array.test.ts` in import order (`describe, it, expect` from vitest, then a blank line, then the relative default import) and in having one `describe` per function.

**Judgement calls (`CLAUDE.md` rule: "match the naming… and idioms of the code around your change")**

1. **Test name style:** `packages/lib/convertToNewDurationType.test.ts:6` and `packages/lib/findDurationType.test.ts:6`. The new names use third-person verbs (`"returns the value unchanged…"`, `"converts minutes to hours"`). `array.test.ts` and most of `packages/lib` use `it("should …")`: there are about 110 `should` names against 33 `returns`. Third-person names already exist in `packages/lib`, so this is a soft mismatch with the nearest neighbour rather than a breach.

**Baseline smells (all judgement calls)**

2. **Duplicated Code:** `packages/lib/convertToNewDurationType.test.ts:6-52`. Twelve `it` blocks repeat the same shape:
   ```ts
   it("converts minutes to hours", () => {
     expect(convertToNewDurationType("minutes", "hours", 120)).toBe(2);
   });
   ```
   Only the arguments change, so a table (`it.each([[prev, next, input, expected], …])`) would remove the repetition. `packages/lib/ssrfProtection.test.ts` already uses `it.each`, so the idiom exists here. `array.test.ts` writes each case out explicitly, though, so the current style is defensible. Low priority.

3. **Inconsistent idiom within the file:** `packages/lib/convertToNewDurationType.test.ts:54-61`. The zero case uses nested `for` loops inside a single `it`, while every other case gets its own `it`. If one of the 9 pairs fails, the message won't say which one. Using `it.each` here too, or naming the pair in the assertion, would keep the file consistent and make failures clear.

4. **Mysterious Name (minor):** `packages/lib/findDurationType.test.ts:23`. The name `"returns days for 0"` records the behaviour but not why: 0 is divisible by 1440, so it falls into the first branch. Something like `"returns days for 0 because it is divisible by 1440"` would tell readers this is pinned on purpose and is not a bug being locked in.

I saw none of the other smells (Feature Envy, Data Clumps, Primitive Obsession, Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains, Middle Man, Refused Bequest). Comment density matches the neighbours: neither file has comments.

The spec docs under `specs/duration-type-tests/` aren't covered by any code standard and aren't counted in the PR-size limits.

## Spec

I found no problems in any of the three categories. Both test files cover everything the spec and issue ask for, every asserted value is correct, and both files pass when run.

**Test run:** `yarn test packages/lib/convertToNewDurationType.test.ts packages/lib/findDurationType.test.ts` passed 2 files and 17 tests. The only other output was an unrelated warning from `packages/testing/src/setupVitest.ts`.

**(a) Missing or partial requirements: none.**
- All 17 acceptance criteria in `specs/duration-type-tests/design.md` map one-to-one to `it` titles in the two test files, worded exactly as the spec lists them.
- "All nine `prevType` → `newType` pairs": three identity cases at `packages/lib/convertToNewDurationType.test.ts:6-16` and six conversions at `:18-40`.
- "Cover at least one such case per lossy direction": minutes→hours, minutes→days and hours→days at `:42-52`.
- "Zero as an input value": all nine pairs in a loop at `:54-61`.
- `findDurationType` days, hours, minutes and the `0` → `"days"` case: `packages/lib/findDurationType.test.ts:6-25`.
- One item can't be checked yet: "mention it in the PR description". There is no PR, so whether the PR body flags the `Math.ceil` rounding and `0` → `"days"` as possible bugs is still open.

**(b) Scope creep: none.**
- The only files changed under `packages/` are the two new test files; neither source function is touched, which meets "Tests only. Do not change the behaviour of either function".
- The other changed files are all under `specs/duration-type-tests/` (the design, plan, gate and decision files). They come from the `/implement-task` workflow that `CLAUDE.md` calls for, so they aren't extra behaviour.
- Testing all nine pairs at zero instead of a single value goes beyond "Zero as an input value", but the spec's own criterion asks for it: "zero input returns 0 for every pair".

**(c) Implemented but wrong: none.** I checked each value against the source code:
- `Math.ceil(90/60)` = 2, `Math.ceil(1500/1440)` = 2 and `Math.ceil(25/24)` = 2, matching the spec's "(90 → 2)", "(1500 → 2)" and "(25 → 2)".
- Exact conversions: 120 minutes is 2 hours, 2880 minutes is 2 days, 48 hours is 2 days, and the reverse directions are 120, 2880 and 48.
- `findDurationType(1500)` gives `"hours"` (1500 % 1440 = 60, and 60 % 60 = 0), and `findDurationType(90)` gives `"minutes"`. Both are good boundary choices.
- Conventions follow `array.test.ts` as the spec describes: `import { describe, it, expect } from "vitest"`, a blank line, the relative import, one `describe` per function, and plain `it` blocks rather than `it.each`.

## Summary

Standards: 4 findings, all judgement calls; the most notable is the zero-input `for` loop at `convertToNewDurationType.test.ts:54-61`, which hides which pair failed. Spec: 0 findings. No `missing` or `wrong` spec findings, so no fix round is needed.

## review.json (not written)

```json
{ "findings": [
  { "axis": "standards", "kind": "smell", "severity": "judgement",
    "summary": "Test names use third-person verbs ('returns…', 'converts…') while the nearest neighbour array.test.ts and most of packages/lib use 'should …'; soft mismatch, not a breach.",
    "where": "packages/lib/convertToNewDurationType.test.ts:6",
    "quote": "CLAUDE.md: match the naming, comment density, and idioms of the code around your change" },
  { "axis": "standards", "kind": "smell", "severity": "judgement",
    "summary": "Possible Duplicated Code: twelve it blocks repeat the same expect(convertToNewDurationType(a, b, n)).toBe(m) shape; it.each would remove it, though array.test.ts writes cases out explicitly.",
    "where": "packages/lib/convertToNewDurationType.test.ts:6",
    "quote": "Duplicated Code — the same logic shape appears in more than one hunk or file in the change." },
  { "axis": "standards", "kind": "smell", "severity": "judgement",
    "summary": "Zero-input case loops over all nine pairs inside one it, unlike the rest of the file; a failure won't name the pair.",
    "where": "packages/lib/convertToNewDurationType.test.ts:54",
    "quote": "CLAUDE.md: match the naming, comment density, and idioms of the code around your change" },
  { "axis": "standards", "kind": "smell", "severity": "judgement",
    "summary": "Possible Mysterious Name: 'returns days for 0' doesn't say this pins current behaviour (0 is divisible by 1440) rather than endorsing it.",
    "where": "packages/lib/findDurationType.test.ts:23",
    "quote": "Mysterious Name — a function, variable, or type whose name doesn't reveal what it does or holds." }
] }
```
