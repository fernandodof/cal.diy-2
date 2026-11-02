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

## ADR-002: The agent's handoff files live outside `.claude/`

### Context

Phase 3 writes `pr-body.md` and Phase 4 writes `review.json` for the harness to
read. In the #33 smoke run, both `Write` calls to `.claude/headless-runs/` were
denied as a "sensitive file" (#51). The fake `claude` writes with bash, so the
tests never hit this.

### Options Considered

1. Allow the path explicitly with `Write(.claude/headless-runs/**)`. A
   real-session probe showed it is still denied: the sensitive-path check wins
   over the allow rule.
2. A permission mode that skips the check. This would loosen every session to fix
   two files.
3. Move both files to a gitignored `.agent-handoff/` at the worktree root. A
   probe showed `Write` succeeds there and creates the directory itself.

### Decision

Option 3. The harness's own run logs stay in `.claude/headless-runs/`, because
bash writes them.

### Consequences

`.gitignore` must carry `.agent-handoff/` on any base a run is cut from.
`scripts/issue-to-pr.test.sh` checks that `headless.md` never names
`.claude/headless-runs`, because the fakes cannot catch a path a real session
is refused.
