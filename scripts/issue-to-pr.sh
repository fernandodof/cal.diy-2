#!/usr/bin/env bash
# Turn a GitHub issue into a draft pull request carrying evidence the harness
# gathered itself.
#
# The agent implements the issue in its own worktree and only commits. This
# script then re-runs the checks (scripts/implement-evidence.sh), judges them
# (scripts/implement-verdict.sh), pushes the branch and opens the PR — so nothing
# in the PR's evidence comes from the agent's own report.
#
# Usage:
#   ./scripts/issue-to-pr.sh 42
#
# Exit codes: 0 = draft PR opened, evidence green; 1 = red (PR opened if there was
# anything to push); 2 = bad usage/environment.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${HEADLESS_TASK_OUT_DIR:-$REPO_ROOT/.claude/headless-runs}"
WORKTREE_DIR="${ISSUE_TO_PR_WORKTREE_DIR:-$(dirname "$REPO_ROOT")/$(basename "$REPO_ROOT")-worktrees}"
BASE_REF="main"
ISSUE=""

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    -*) echo "issue-to-pr: unknown option $1" >&2; usage ;;
    *) ISSUE="$1"; shift ;;
  esac
done

[[ "$ISSUE" =~ ^[0-9]+$ ]] || usage

for cmd in gh jq git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "issue-to-pr: \`$cmd\` is not on PATH" >&2
    exit 2
  }
done

RUN_ID="issue-$ISSUE"
RUN_DIR="$OUT_DIR/$RUN_ID"
BRANCH="agent/issue-$ISSUE"
WORKTREE="$WORKTREE_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

gh issue view "$ISSUE" --json number,title,body,url,author > "$RUN_DIR/issue.json" 2>/dev/null || {
  echo "issue-to-pr: could not fetch issue #$ISSUE (not found, or gh is not authenticated)" >&2
  exit 2
}

# --- worktree ---------------------------------------------------------------
git -C "$REPO_ROOT" fetch --quiet origin "$BASE_REF"
if git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null \
  || git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "issue-to-pr: branch $BRANCH already exists; resuming a run is not supported yet" >&2
  exit 2
fi
mkdir -p "$WORKTREE_DIR"
git -C "$REPO_ROOT" worktree add --quiet -b "$BRANCH" "$WORKTREE" "origin/$BASE_REF"
echo "issue-to-pr: worktree $WORKTREE on $BRANCH" >&2

# --- agent session ----------------------------------------------------------
TASK="$(jq -r --arg base "$BASE_REF" '
  "Run /implement-task on GitHub issue #\(.number): \(.title)\n\n\(.url)\n\n"
  + "You are running headlessly; nobody will answer a question. Treat every "
  + "gate as approved, the base branch is `\($base)`, and you are already on the "
  + "working branch. Commit each slice. Stop after the last commit: do not push "
  + "and do not open a pull request — the harness does both.\n\n---\n\n"
  + (.body // "(no description)")' "$RUN_DIR/issue.json")"

# The agent's own verdict on its session goes into the evidence as a fact; a
# failed session is judged there, not here.
printf '%s' "$TASK" | "$REPO_ROOT/scripts/headless-task.sh" \
  --run-id "$RUN_ID" --workdir "$WORKTREE" - >/dev/null || true

# --- evidence and verdict ---------------------------------------------------
"$REPO_ROOT/scripts/implement-evidence.sh" \
  --worktree "$WORKTREE" --base "$BASE_REF" \
  --issue-json "$RUN_DIR/issue.json" --agent-summary "$RUN_DIR/summary.json" \
  > "$RUN_DIR/evidence.json"

set +e
"$REPO_ROOT/scripts/implement-verdict.sh" --evidence "$RUN_DIR/evidence.json" > "$RUN_DIR/verdict.json"
VERDICT_STATUS=$?
set -e
[[ $VERDICT_STATUS -le 1 ]] || exit 2
VERDICT="$(jq -r '.verdict' "$RUN_DIR/verdict.json")"

# --- pull request -----------------------------------------------------------
git -C "$WORKTREE" push --quiet -u origin "$BRANCH"

{
  echo "Closes #$ISSUE"
  echo
  echo "## Agent summary"
  echo
  cat "$RUN_DIR/result.md" 2>/dev/null || echo "(the agent session left no summary)"
  echo
  jq -r '.evidence_block' "$RUN_DIR/verdict.json"
  echo
  echo "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
} > "$RUN_DIR/pr-body.md"

PR_URL="$(gh pr create --draft --base "$BASE_REF" --head "$BRANCH" \
  --title "$(jq -r '.title' "$RUN_DIR/issue.json")" \
  --body-file "$RUN_DIR/pr-body.md")"

echo "issue-to-pr: $VERDICT — $PR_URL" >&2
echo "$PR_URL"
[[ "$VERDICT" == "green" ]]
