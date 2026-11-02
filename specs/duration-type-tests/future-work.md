# Duration Type Tests Future Work

Ideas and enhancements deferred from initial implementation.

## Enhancements

## Technical Debt

- Decide whether `Math.ceil` rounding in `convertToNewDurationType` and
  `findDurationType(0) === "days"` are intended (see `decisions.md` ADR-001).

## Nice to Have

- Coverage for negative values and `NaN`, which the issue did not ask for.
