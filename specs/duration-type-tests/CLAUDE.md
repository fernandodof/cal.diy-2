# CLAUDE.md — Duration Type Tests

## Project Context

Unit tests for `convertToNewDurationType` and `findDurationType` in `packages/lib/`
(issue #11). Tests only; neither function changes.

## Before Starting Work

1. Read specs/duration-type-tests/design.md
2. Check specs/duration-type-tests/implementation.md for current progress
3. Look at existing patterns in `packages/lib/array.test.ts`

## Code Patterns

- `import { describe, it, expect } from "vitest"`, one `describe` per function.
- Plain `it` blocks whose titles match the acceptance criteria in design.md exactly.
- Verify with `yarn test packages/lib/convertToNewDurationType.test.ts packages/lib/findDurationType.test.ts`.

## Don't

- Don't add features not in design.md
- Don't skip tests
- Don't change `convertToNewDurationType.ts` or `findDurationType.ts` — assert today's
  behaviour (`Math.ceil` rounding up, `0` → `"days"`) and note it in the PR body
