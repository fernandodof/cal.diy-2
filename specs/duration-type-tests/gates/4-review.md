Outcome: continue

Review of `git diff origin/main...HEAD` (fixed point `origin/main` @ c138cab7ea).
Spec: `specs/duration-type-tests/design.md` + issue #11. Standards: `CONTRIBUTING.md`
plus the smell baseline. Two reviewers ran in parallel. Their reports appear below as
written, except that line numbers were corrected after checking them against the file.

## Standards

**Sources checked:** CONTRIBUTING.md, specs/README.md, SPEC-WORKFLOW.md, neighbouring `packages/lib/*.test.ts` (`array.test.ts`, `ssrfProtection.test.ts`), and the Fowler baseline. Biome handles formatting and import order, so I left those out.

### Hard violations (documented standards)

None found.

- CONTRIBUTING.md says almost nothing about tests (its Testing section reads "coming soon"). Its file-naming rules keep the `.test.ts` suffix, and both new files use it next to their source.
- Both files follow the house style of `packages/lib` tests: vitest `describe`/`it`, `"should …"` titles, default import from the sibling module.
- specs/README.md's "PR reviewable in under 10 minutes" rule caps a PR at 5–7 files excluding tests and 500 lines. This PR has 8 spec files, so it is just over the cap, at 412 lines total. It is borderline, not a clear breach.

### Judgement calls

**packages/lib/convertToNewDurationType.test.ts:11-33 — Duplicated Code.** Six `it` blocks have the same shape:
```ts
it("should convert minutes to hours", () => {
  expect(convertToNewDurationType("minutes", "hours", 120)).toBe(2);
});
```
The rounding cases at :35-45 repeat that shape three more times. The repo already uses `it.each` for table cases (`packages/lib/ssrfProtection.test.ts:17,31,42`). Using `it.each([["minutes","hours",120,2], …])("should convert %s to %s", …)` would make the file shorter. This is optional: one `it` per case is also common upstream and gives clearer failure names.

**packages/lib/convertToNewDurationType.test.ts:47-54 — style inconsistency.** The zero case uses a nested `for` loop over `["minutes","hours","days"] as const` inside one `it`, while the rest of the file uses one explicit `it` per case. If one pair fails, the message doesn't say which. `it.each` would fix both problems. Minor.

**packages/lib/convertToNewDurationType.test.ts:48 — Primitive Obsession (minor).** It redeclares the duration-type union as a local literal array instead of using the exported type, so the list can drift from the type. Low impact in a test.

**packages/lib/findDurationType.test.ts:1-24.** Clean, no smells. Test values like `1440` and `60` are written as literals rather than the exported `MINUTES_IN_DAY` / `MINUTES_IN_HOUR`. That is fine for pinning tests, which often hard-code values on purpose.

**specs/duration-type-tests/gates/.** specs/README.md and SPEC-WORKFLOW.md don't define a `gates/` subfolder. Adding one isn't forbidden. The folder also leaves out `prompts.md` and `docs/`, but `specs/issue-to-pr-harness/` leaves out the same files, so that matches existing practice.

### Not flagged
Feature Envy, Data Clumps, Repeated Switches, Shotgun/Divergent Change, Speculative Generality, Message Chains, Middle Man and Refused Bequest don't apply to two small test files.

## Spec

I found no blocking issues. All 15 Acceptance Criteria in `specs/duration-type-tests/design.md:27-41` map to a test with the exact name the spec gives. I checked every asserted value against `packages/lib/convertToNewDurationType.ts` and `packages/lib/findDurationType.ts`, and they match how the code behaves today. `yarn test packages/lib/convertToNewDurationType.test.ts packages/lib/findDurationType.test.ts` passes: 2 files, 15 tests.

**(a) Missing or partial**
- None in the code.
- One item can't be checked yet. The issue says: "if something looks like a bug (the Math.ceil rounding, or 0 returning "days"), assert what the code does today and mention it in the PR description". The tests do assert today's behaviour (`packages/lib/convertToNewDurationType.test.ts:35-45`, `packages/lib/findDurationType.test.ts:21-23`), and `design.md:88-92` plans to flag both in the PR description. No PR exists yet, so check this when the PR is opened.

**(b) Scope creep**
- None in the code. The only non-test changes are the spec folder files (`specs/duration-type-tests/*`), which the `/implement-task` workflow produces.
- No source files are touched, which satisfies "Tests only. Do not change the behaviour of either function".

**(c) Looks implemented but wrong**
- None. Each value below matches the source:
  - "All nine prevType → newType pairs": the three identity pairs are at `convertToNewDurationType.test.ts:5-9` and the six exact conversions at `:11-33`. 120 min→2 h, 2880 min→2 d, 2 h→120 min, 48 h→2 d, 2 d→2880 min and 2 d→48 h all follow from the 60/1440/24 constants.
  - "Cover at least one such case per lossy direction": 90 min→2 h, 1441 min→2 d and 25 h→2 d (`:35-45`) are all correct under `Math.ceil`.
  - "Zero as an input value": `:47-54` loops over all nine pairs and expects 0.
  - findDurationType: 1440 and 2880 return "days". 60 and 120 return "hours". 1, 45 and 90 return "minutes". 0 returns "days" (`findDurationType.test.ts:21-23`), matching "0 is divisible by both, so it returns "days"".
- Conventions: the issue asks for "one describe per function". Both files have exactly one `describe`. The import order is `describe, expect, it`, which is biome's sorted order and imports the same names, so this is not a defect.

---

**Summary.** Standards: 0 hard violations and 4 judgement calls. The most significant is repeated `it` blocks where `it.each` could be used (`convertToNewDurationType.test.ts:11-45`). Spec: 0 findings of kind missing, creep or wrong. The only open item is that the PR description must still mention the `Math.ceil` and `0 → "days"` behaviours.
