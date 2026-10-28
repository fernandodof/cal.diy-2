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

# The worktree needs its own install. Workspace packages are linked relatively
# (node_modules/@calcom/* -> ../../packages/*), so borrowing this checkout's
# node_modules would resolve them here, and the evidence would test the wrong
# code. Reusing this checkout's cache keeps the install offline.
echo "issue-to-pr: installing dependencies in the worktree" >&2
(cd "$WORKTREE" && YARN_CACHE_FOLDER="$REPO_ROOT/.yarn/cache" yarn install --immutable) \
  > "$RUN_DIR/install.log" 2>&1 || {
  echo "issue-to-pr: yarn install failed in $WORKTREE; see $RUN_DIR/install.log" >&2
  exit 2
}

# --- agent sessions ---------------------------------------------------------
# What the agent may run: enough to implement and verify its own work, which the
# #11 run was denied. Pushing and opening PRs are the harness's, and the deny list
# keeps them that way even if the allow list or permission mode is loosened.
ALLOWED_TOOLS="Read,Edit,Write,Glob,Grep,Skill"
ALLOWED_TOOLS+=",Bash(yarn test:*),Bash(yarn biome:*),Bash(yarn turbo run type-check:*)"
ALLOWED_TOOLS+=",Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git add:*),Bash(git commit:*)"
ALLOWED_TOOLS+=",Bash(ls:*),Bash(cat:*),Bash(grep:*),Bash(find:*),Bash(gh issue view:*)"
DISALLOWED_TOOLS="Bash(git push:*),Bash(gh pr:*)"

ISSUE_URL="$(jq -r '.url' "$RUN_DIR/issue.json")"
SPEC=""

# The spec folder is the agent's choice — Phase 1 may extend an existing one —
# so it is found from what the branch added, not predicted. More than one
# candidate is as good as none.
resolve_spec() {
  local found
  found="$(git -C "$WORKTREE" diff --name-only --diff-filter=A "origin/$BASE_REF" HEAD -- 'specs/*/gates/1-research.md')"
  [[ -n "$found" && "$(wc -l <<<"$found")" -eq 1 ]] && dirname "$(dirname "$found")"
}

# One session per phase, each reading only the previous phase's handoff file.
# Every session's summary goes into the evidence as a fact; whether the sequence
# should have stopped is judged there, not here.
: > "$RUN_DIR/phases.jsonl"
n=0
for phase in 1-research 2-plan 3-implement; do
  n=$((n + 1))
  TASK="/implement-task --headless --phase $n --base $BASE_REF $ISSUE_URL${SPEC:+ --spec $SPEC}"
  if [[ $n -eq 1 ]]; then
    TASK+="$(jq -r '"\n\n# Issue #\(.number): \(.title)\n\n" + (.body // "(no description)")' "$RUN_DIR/issue.json")"
  fi
  echo "issue-to-pr: phase $phase" >&2
  printf '%s' "$TASK" | "$REPO_ROOT/scripts/headless-task.sh" \
    --run-id "$RUN_ID/$phase" --workdir "$WORKTREE" \
    --allowed-tools "$ALLOWED_TOOLS" --disallowed-tools "$DISALLOWED_TOOLS" \
    - >/dev/null 2>&1 || true

  [[ $n -eq 1 ]] && SPEC="$(resolve_spec || true)"
  OUTCOME=""
  if [[ -n "$SPEC" && -f "$WORKTREE/$SPEC/gates/$phase.md" ]]; then
    [[ "$(head -1 "$WORKTREE/$SPEC/gates/$phase.md")" =~ ^Outcome:\ (continue|blocked)$ ]] \
      && OUTCOME="${BASH_REMATCH[1]}"
  fi
  jq -c --arg phase "$phase" --arg outcome "$OUTCOME" \
    '{phase: $phase, status, turns, cost_usd, outcome: (if $outcome == "" then null else $outcome end)}' \
    "$RUN_DIR/$phase/summary.json" >> "$RUN_DIR/phases.jsonl" 2>/dev/null \
    || jq -nc --arg phase "$phase" '{phase: $phase, status: null, turns: null, cost_usd: null, outcome: null}' >> "$RUN_DIR/phases.jsonl"
done
jq -s . "$RUN_DIR/phases.jsonl" > "$RUN_DIR/phases.json"

# --- evidence and verdict ---------------------------------------------------
"$REPO_ROOT/scripts/implement-evidence.sh" \
  --worktree "$WORKTREE" --base "$BASE_REF" \
  --issue-json "$RUN_DIR/issue.json" --phases "$RUN_DIR/phases.json" ${SPEC:+--spec "$SPEC"} \
  > "$RUN_DIR/evidence.json"

set +e
"$REPO_ROOT/scripts/implement-verdict.sh" --evidence "$RUN_DIR/evidence.json" > "$RUN_DIR/verdict.json"
VERDICT_STATUS=$?
set -e
[[ $VERDICT_STATUS -le 1 ]] || exit 2
VERDICT="$(jq -r '.verdict' "$RUN_DIR/verdict.json")"

# A branch with nothing on it cannot back a PR. The verdict already says why;
# say it here too, since there is no PR to carry it.
if [[ "$(jq -r '.commits // 0' "$RUN_DIR/evidence.json")" -eq 0 ]]; then
  echo "issue-to-pr: red — the agent made no commits, so there is no PR to open" >&2
  jq -r '.reasons[] | "  - " + .' "$RUN_DIR/verdict.json" >&2
  exit 1
fi

# --- labels -----------------------------------------------------------------
# Created on first use, so a fresh fork needs no setup. Existing labels are left
# as they are: someone may have recoloured or described them.
EXISTING_LABELS="$(gh label list --limit 200 --json name --jq '.[].name')"
while IFS='|' read -r name color description; do
  grep -qxF "$name" <<<"$EXISTING_LABELS" && continue
  gh label create "$name" --color "$color" --description "$description" >/dev/null
done <<'LABELS'
agent:implement|5319E7|Hand this issue to the issue-to-PR harness
agent:needs-clarification|FBCA04|Too ambiguous for the harness to implement as written
agent:needs-help|D93F0B|The harness opened this PR, but its evidence is red
LABELS

# --- pull request -----------------------------------------------------------
git -C "$WORKTREE" push --quiet -u origin "$BRANCH"

{
  echo "Closes #$ISSUE"
  echo
  cat "$WORKTREE/.claude/headless-runs/pr-body.md" 2>/dev/null \
    || echo "_The agent left no PR body draft; the evidence below is all there is._"
  echo
  if [[ -n "$SPEC" ]]; then
    echo "### Gates"
    echo
    for gate in "$WORKTREE/$SPEC"/gates/*.md; do
      [[ -f "$gate" ]] && echo "- \`$SPEC/gates/$(basename "$gate")\` — $(head -1 "$gate")"
    done
    echo
  fi
  jq -r '.evidence_block' "$RUN_DIR/verdict.json"
  echo
  echo "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
} > "$RUN_DIR/pr-body.md"

LABEL_ARGS=()
while IFS= read -r label; do
  [[ -n "$label" ]] && LABEL_ARGS+=(--label "$label")
done < <(jq -r '.labels[]' "$RUN_DIR/verdict.json")

PR_URL="$(gh pr create --draft --base "$BASE_REF" --head "$BRANCH" \
  --title "$(jq -r '.title' "$RUN_DIR/issue.json")" \
  --body-file "$RUN_DIR/pr-body.md" \
  ${LABEL_ARGS[@]+"${LABEL_ARGS[@]}"})"

echo "issue-to-pr: $VERDICT — $PR_URL" >&2
echo "$PR_URL"
[[ "$VERDICT" == "green" ]]
