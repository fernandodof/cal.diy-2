# Issue-to-PR Harness Decisions

## ADR-001: The worktree runs its own `yarn install`

### Context

Each run works in a fresh git worktree. `.yarnrc.yml` sets
`nodeLinker: node-modules`, and the workspace packages in `node_modules/@calcom/`
are relative symlinks (e.g. `alby -> ../../packages/app-store/alby`).

### Options Considered

1. Symlink the main checkout's `node_modules` into the worktree — instant, but the
   relative links resolve against the main checkout, so `@calcom/*` imports load
   the main checkout's sources and the evidence tests the wrong code.
2. `yarn install --immutable` in the worktree with `YARN_CACHE_FOLDER` pointed at
   the main checkout's `.yarn/cache` (`enableGlobalCache: false`) — minutes per run,
   no re-download, and the worktree's code is what runs.
3. No worktree; run in the main checkout — fast, but touches the user's checkout.

### Decision

Option 2.

### Consequences

Each run pays an install. Evidence is about the code on the branch, which is the
point of gathering it.
