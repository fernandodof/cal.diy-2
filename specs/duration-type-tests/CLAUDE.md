# CLAUDE.md — Duration Type Tests

## Project Context

Unit tests for `packages/lib/convertToNewDurationType.ts` and
`packages/lib/findDurationType.ts` (issue #11). Tests only: the functions'
behaviour is pinned as it is today, not changed.

## Before Starting Work

1. Read specs/duration-type-tests/design.md
2. Check specs/duration-type-tests/implementation.md for current progress
3. Look at existing patterns in `packages/lib/array.test.ts`

## Code Patterns

- `import { describe, it, expect } from "vitest";`, blank line, then the relative
  default import of the module under test.
- One `describe` per function, titled with the function name; `it` titles must
  match the Acceptance Criteria in design.md exactly — the harness looks tests up
  by full name.
- Run with `yarn test packages/lib/convertToNewDurationType.test.ts packages/lib/findDurationType.test.ts`.

## Don't

- Don't add features not in design.md
- Don't skip tests
- Don't modify `convertToNewDurationType.ts` or `findDurationType.ts` — assert the
  `Math.ceil` rounding and `findDurationType(0) === "days"` as they are, and note
  them in the PR description instead
