Outcome: continue

Both slices are complete, each in its own commit. All 8 tests in
`packages/lib/text.test.ts` pass. `yarn turbo run type-check --filter=@calcom/web`
passes. `tsc -p packages/lib/tsconfig.json` reports no errors in the changed
files. `biome check` passes, with only nursery infos (`useExplicitType`,
`noTernary`) that also fire on the existing `truncate`.

`git diff main --stat` (taken before this gate file was added):

```
 packages/lib/text.test.ts                          | 101 ++++++++++++++++++++-
 packages/lib/text.ts                               |   9 +-
 specs/truncate-on-word-max-length/CLAUDE.md        |  30 ++++++
 specs/truncate-on-word-max-length/decisions.md     |  20 ++++
 specs/truncate-on-word-max-length/design.md        |  97 ++++++++++++++++++++
 specs/truncate-on-word-max-length/future-work.md   |   9 ++
 .../gates/1-research.md                            |  39 ++++++++
 specs/truncate-on-word-max-length/gates/2-plan.md  |  20 ++++
 .../truncate-on-word-max-length/implementation.md  |  57 ++++++++++++
 9 files changed, 376 insertions(+), 6 deletions(-)
```
