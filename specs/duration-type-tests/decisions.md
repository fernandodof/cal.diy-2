# Duration Type Tests Decisions

## ADR-001: Assert current behaviour for `Math.ceil` rounding and `0` → `"days"`

### Context

Issue #11 asks for tests only, and names two behaviours that may be bugs.

### Options Considered

1. Fix them — out of scope; the issue forbids behaviour changes.
2. Assert them as they are and flag them in the PR — keeps the PR test-only.

### Decision

Option 2.

### Consequences

- A later fix to either behaviour has to update these tests on purpose.
