# Duration Type Tests Decisions

## ADR-001: Assert current behaviour for rounding and zero

### Context

`convertToNewDurationType` passes every result through `Math.ceil`, so lossy
conversions round up (90 minutes → 2 hours). `findDurationType(0)` returns
`"days"` because `0 % 1440 === 0`. Either could be read as a bug.

### Options Considered

1. Fix the behaviour alongside the tests — out of scope; issue #11 says tests only.
2. Assert today's behaviour and flag it in the PR description — what the issue asks.

### Decision

Option 2. Tests pin what the code does today.

### Consequences

- If either behaviour is later changed on purpose, the matching test changes with it.
