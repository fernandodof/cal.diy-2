# CLAUDE.md — Issue-to-PR Harness

## Project Context

A local harness that turns a GitHub issue into a draft PR carrying evidence the
harness gathered itself, by running `/implement-task` headlessly in a worktree and
then re-running the checks independently. Parent PRD: #23.

## Before Starting Work

1. Read specs/issue-to-pr-harness/design.md
2. Check specs/issue-to-pr-harness/implementation.md for current progress
3. Look at existing patterns in scripts/pr-evidence.sh, scripts/pr-self-approval.sh,
   scripts/pr-self-approval.test.sh and scripts/headless-task.sh

## Code Patterns

- Collector gathers, judge decides: the collector never decides anything, the
  judge never does I/O. Unreachable facts are `null`, and `null` is a failure.
- Bash with `set -euo pipefail`, a header comment whose usage block `usage()`
  prints via `sed -n`, `jq` for all JSON, exit codes `0` / `1` / `2 = usage or environment`.
- Tests are plain bash scripts with a `check name expected actual` helper, as in
  `scripts/pr-self-approval.test.sh`.

## Don't

- Don't add features not in design.md
- Don't skip tests
- Don't let the agent push or open the PR — permissions enforce it, not the prompt
- Don't symlink the main checkout's `node_modules` into the worktree
- Don't copy any check result from the agent's output into the evidence
