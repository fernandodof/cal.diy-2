Outcome: continue

Review of `git diff origin/main...HEAD` (6 commits, `0fb3bd1475`..`138e1cd8b3`).
Spec: `specs/duration-type-tests/design.md` + issue #11. Standards: `CONTRIBUTING.md` + smell baseline.

## Standards

**Hard violations: none.** CONTRIBUTING.md has no rules for test code beyond file naming. Its "File Naming Conventions" section keeps `.test.ts` for tests, and both new files (`convertToNewDurationType.test.ts`, `findDurationType.test.ts`) follow it. They also sit next to their source files, like `packages/lib/array.test.ts`. The PR-level rules (under 500 LOC, under 10 code files, one concern) are met: 2 code files and 88 added lines. Imports, the vitest `describe`/`it`/`expect` usage and formatting are biome's job, so I left them out.

**Judgement calls**

1. **Test name style differs from the neighbouring tests** (no documented rule)
   - `packages/lib/convertToNewDurationType.test.ts:6-53` and `packages/lib/findDurationType.test.ts:6-23` use present-tense names such as `it("returns the value unchanged when converting minutes to minutes"`.
   - `array.test.ts` uses `it("should remove duplicates ...")`. A grep of `packages/lib` finds about 209 `it("should` names across 29 test files, so the `should` style is common there.
   - No standard requires it, and CLAUDE.md asks to "match the naming… of the code around your change". This is a minor consistency point, not a breach.

2. **Duplicated Code** in `convertToNewDurationType.test.ts:6-53`
   - There are 12 blocks with the same shape: `it("converts X to Y", () => { expect(convertToNewDurationType(a, b, n)).toBe(m); });`. The three identity cases (lines 6-16) and the three rounding cases (lines 42-52) repeat that shape exactly.
   - An `it.each` table would remove the repetition. The repo does use it, but only rarely (one file, `ssrfProtection.test.ts`), so the explicit style is equally defensible. This is low priority.
   - The same file is not consistent with itself: lines 54-61 test zero with a nested loop over `durationTypes`, while the other cases are written out one by one. Either approach is fine, but mixing them reads oddly.

3. **Several assertions per `it`** in `findDurationType.test.ts:6-23`
   - For example, `expect(findDurationType(60)).toBe("hours"); expect(findDurationType(120))...; expect(findDurationType(1500))...` sits in one block.
   - `array.test.ts` also puts more than one `expect` in a block, so this is not a breach. It is only noted because the other new file uses one assertion per case.

4. **The test names repeat the unit sizes as magic numbers** (`findDurationType.test.ts:6,11,17`)
   - The names say "divisible by 1440" and "divisible by 60". These numbers mirror the implementation, so in tests they are acceptable as documentation. I'm not flagging this as Primitive Obsession; the domain type is already the `"minutes" | "hours" | "days"` string union.

**No other baseline smells.** Feature Envy, Data Clumps, Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains, Middle Man and Refused Bequest don't apply to two small, self-contained test files. The spec docs under `specs/duration-type-tests/` are outside the code standards and were not reviewed.

**Verdict:** the branch is conformant. The only suggestions are optional: switch to the `should …` naming and consider `it.each` for the conversion table.

## Spec

The two test files cover all 17 Acceptance Criteria, and every assertion matches what the code does today. All 17 tests pass when I run `yarn test packages/lib/convertToNewDurationType.test.ts packages/lib/findDurationType.test.ts`. Neither function under test was changed.

**(a) Missing or partial requirements**

- **PR-description notes can't be checked yet.** Issue: "if something looks like a bug (the Math.ceil rounding, or 0 returning "days"), assert what the code does today and mention it in the PR description". Design › Edge Cases says the same ("flagged in the PR description"). The asserts are there (`packages/lib/convertToNewDurationType.test.ts:42-52`, `packages/lib/findDurationType.test.ts:23-25`). No PR exists yet, so whoever opens it needs to add both notes.
- **The test files were never type-checked.** This isn't a spec requirement, but `specs/duration-type-tests/gates/3-implement.md` admits "the test files were not type-checked". The risk is low because the literals match `DurationType` and `as const` is used at `convertToNewDurationType.test.ts:55`.

**(b) Scope creep**

- **Two unfilled template files.** `specs/duration-type-tests/decisions.md:1` is still the raw template ("# {Feature Name} Decisions", "## ADR-001: {Decision Title}"). `specs/duration-type-tests/future-work.md:1` is the same ("# {Feature Name} Future Work", with empty sections). Neither the spec nor the issue asks for them. They are workflow scaffolding with no content, so either fill them in or delete them.
- Beyond that, the only changes are the two test files and the spec folder. No production code is touched.

**(c) Implemented, but looks wrong**

Nothing. I checked every assertion against the source:

- **The nine conversion pairs** (`convertToNewDurationType.test.ts:6-40`) all match the functions in the map in `packages/lib/convertToNewDurationType.ts`. Each "converts X to Y" case uses an even multiple, so it tests the factor and not the rounding.
- **Rounding up** (design: "90 min → 2 h, 1441 min → 2 d, 25 h → 2 d"). The tests at lines 43, 47 and 51 assert exactly those values: 1.5, 1.0007 and 1.0417, each rounded up to 2.
- **Zero** (design: "Zero input returns 0 for every pair"). Lines 54-61 loop over all 9 pairs with `toBe(0)`. That is a stronger check than the issue's "Zero as an input value".
- **`findDurationType`** (`findDurationType.test.ts:6-25`):
  - 1500 is divisible by 60 but not by 1440, so "hours" is correct.
  - 1441 is a good "minutes" edge case.
  - 0 → "days" matches the source.
- **Conventions** (design: "`import { describe, it, expect } from "vitest";`, a blank line, then the relative import … one `describe` per function"). Both files follow this at lines 1-5. The `it` titles match the Acceptance Criteria names exactly.

## Summary

Standards: 4 judgement calls, 0 hard violations. The worst is the test-name style (`returns …` rather than the neighbouring `should …`).
Spec: 1 scope-creep item (the unfilled `decisions.md` / `future-work.md` templates) and 0 wrong. The item under (a) was checked after the review: `.agent-handoff/pr-body.md:5-6` already mentions both the `Math.ceil` rounding and `0 → "days"`. That requirement is met, so `review.json` doesn't record it as `missing`. The type-check note is not a spec requirement, so it isn't recorded as a finding either. Nothing here needs a fix round.
