Outcome: continue

Base: `main` (recorded in `implementation.md` › Session Notes).

`git diff main --stat` (before this gate file was added):

```
 packages/lib/convertToNewDurationType.test.ts |  62 +++++++++++++++
 packages/lib/findDurationType.test.ts         |  26 ++++++
 specs/duration-type-tests/CLAUDE.md           |  30 +++++++
 specs/duration-type-tests/decisions.md        |  20 +++++
 specs/duration-type-tests/design.md           | 109 ++++++++++++++++++++++++++
 specs/duration-type-tests/future-work.md      |   9 +++
 specs/duration-type-tests/gates/1-research.md |  38 +++++++++
 specs/duration-type-tests/gates/2-plan.md     |  23 ++++++
 specs/duration-type-tests/implementation.md   |  61 ++++++++++++++
 9 files changed, 378 insertions(+)
```

Checks:

- `yarn test packages/lib/findDurationType.test.ts` — 4 passed
- `yarn test packages/lib/convertToNewDurationType.test.ts` — 13 passed
- `yarn turbo run type-check --filter=@calcom/web` — passed, but it does not cover the
  new test files (nothing in `@calcom/web` imports them). A direct `tsc` on
  `packages/lib` was not permitted in this session, so the test files were not
  type-checked.
