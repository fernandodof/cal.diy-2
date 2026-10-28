#!/usr/bin/env bash
# Collect the evidence for an agent-implemented branch, as one JSON document.
#
# This script re-runs the checks itself. It never reads a result the agent
# reported, and it never decides anything: `scripts/implement-verdict.sh` judges
# the document. Facts it cannot reach are emitted as null.
#
# Usage:
#   ./scripts/implement-evidence.sh --worktree <dir> --base main \
#     --issue-json issue.json --phases phases.json [--spec specs/<slug>]
#
# Exit codes: 0 = evidence collected, 2 = bad usage/environment.
#
# Output: a JSON object on stdout. See docs/harness/implement-evidence-schema.md.

set -euo pipefail

WORKTREE=""
BASE_REF=""
ISSUE_JSON=""
PHASES_FILE=""
SPEC=""
LOG_TAIL_LINES=40

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree) WORKTREE="${2:-}"; shift 2 ;;
    --base) BASE_REF="${2:-}"; shift 2 ;;
    --issue-json) ISSUE_JSON="${2:-}"; shift 2 ;;
    --phases) PHASES_FILE="${2:-}"; shift 2 ;;
    --spec) SPEC="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "implement-evidence: unknown argument $1" >&2; usage ;;
  esac
done

[[ -d "$WORKTREE" && -n "$BASE_REF" && -f "$ISSUE_JSON" ]] || usage

for cmd in jq git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "implement-evidence: \`$cmd\` is not on PATH" >&2
    exit 2
  }
done

g() { git -C "$WORKTREE" "$@"; }

HEAD_SHA="$(g rev-parse HEAD)"
BRANCH="$(g rev-parse --abbrev-ref HEAD)"
MERGE_BASE="$(g merge-base "origin/$BASE_REF" HEAD 2>/dev/null || true)"

# Everything measured against the base is null without a merge base: a diff
# against the wrong commit would describe someone else's changes.
COMMITS="null"
DIFF="null"
CHANGED_FILES=()
if [[ -n "$MERGE_BASE" ]]; then
  COMMITS="$(g rev-list --count "$MERGE_BASE..HEAD")"
  while IFS= read -r path; do
    [[ -n "$path" ]] && CHANGED_FILES+=("$path")
  done < <(g diff --name-only --diff-filter=d "$MERGE_BASE" HEAD)
  DIFF="$(g diff --numstat "$MERGE_BASE" HEAD | jq -R -s '
    split("\n") | map(select(length > 0) | split("\t")) as $rows
    | {files_changed: ($rows | length),
       insertions: ($rows | map(.[0] | tonumber? // 0) | add // 0),
       deletions:  ($rows | map(.[1] | tonumber? // 0) | add // 0),
       changed_files: ($rows | map(.[2]))}')"
fi

# One record per phase session the harness started, in order, and their sum.
# The sum is only "completed" when all three phases ran, completed and chose to
# continue — anything less is a sequence that stopped short.
PHASES="null"
AGENT="null"
if [[ -f "$PHASES_FILE" ]] && jq -e 'type == "array" and length > 0' "$PHASES_FILE" >/dev/null 2>&1; then
  PHASES="$(jq . "$PHASES_FILE")"
  AGENT="$(jq '{
    status: (if any(.[]; .status == "failed") then "failed"
             elif any(.[]; .outcome == "blocked") then "blocked"
             elif length < 3 or any(.[]; .status != "completed" or .outcome != "continue") then "incomplete"
             else "completed" end),
    turns: (map(.turns // 0) | add),
    cost_usd: (map(.cost_usd // 0) | add)
  }' "$PHASES_FILE")"
fi

# Run one check in the worktree and print its record. A check that cannot be run
# at all is recorded with a null exit code rather than skipped, so its absence
# shows up in the verdict.
run_check() {
  local name="$1" source="$2"; shift 2
  local log exit_code
  log="$(mktemp)"
  if [[ $# -eq 0 ]]; then
    exit_code="null"
    echo "not run: nothing to check" > "$log"
  else
    set +e
    (cd "$WORKTREE" && "$@") > "$log" 2>&1
    exit_code=$?
    set -e
  fi
  jq -n \
    --arg name "$name" \
    --arg command "$*" \
    --arg source "$source" \
    --argjson exit_code "$exit_code" \
    --arg log_tail "$(tail -n "$LOG_TAIL_LINES" "$log")" \
    '{name: $name, command: $command, source: $source, exit_code: $exit_code, log_tail: $log_tail}'
  rm -f "$log"
}

CHECKS="$(
  {
    # Only @calcom/web has a type-check task, and it compiles what it imports,
    # so it is the one that covers changes in packages/lib, features and trpc.
    run_check type-check always yarn turbo run type-check --filter=@calcom/web
    # Biome exits 0 having checked nothing when no changed file is one it reads,
    # so pass it only files it reads; with none, the check did not run.
    BIOME_FILES=()
    for path in ${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}; do
      [[ "$path" =~ \.(js|jsx|mjs|cjs|ts|tsx|mts|cts|json|jsonc|css)$ ]] && BIOME_FILES+=("$path")
    done
    if [[ ${#BIOME_FILES[@]} -gt 0 ]]; then
      run_check biome always yarn biome check --no-errors-on-unmatched "${BIOME_FILES[@]}"
    else
      run_check biome always
    fi
  } | jq -s .
)"

jq -n \
  --arg collected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile issue "$ISSUE_JSON" \
  --arg base_ref "$BASE_REF" \
  --arg merge_base "$MERGE_BASE" \
  --arg branch "$BRANCH" \
  --arg head_sha "$HEAD_SHA" \
  --argjson commits "$COMMITS" \
  --argjson agent "$AGENT" \
  --argjson phases "$PHASES" \
  --arg spec "$SPEC" \
  --argjson diff "$DIFF" \
  --argjson checks "$CHECKS" \
  '{
    schema: "implement-evidence/1",
    collected_at: $collected_at,
    issue: ($issue[0] | {number, url, title, author: (.author.login // .author // "")}),
    base_ref: $base_ref,
    merge_base: (if $merge_base == "" then null else $merge_base end),
    branch: $branch,
    head_sha: $head_sha,
    commits: $commits,
    spec: (if $spec == "" then null else $spec end),
    agent: $agent,
    phases: $phases,
    diff: $diff,
    checks: $checks
  }'
