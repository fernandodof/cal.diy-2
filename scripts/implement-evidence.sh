#!/usr/bin/env bash
# Collect the evidence for an agent-implemented branch, as one JSON document.
#
# This script re-runs the checks itself. It never reads a result the agent
# reported, and it never decides anything: `scripts/implement-verdict.sh` judges
# the document. Facts it cannot reach are emitted as null.
#
# Usage:
#   ./scripts/implement-evidence.sh --worktree <dir> --base main \
#     --issue-json issue.json --phases phases.json --budget budget.json [--spec specs/<slug>]
#
# Exit codes: 0 = evidence collected, 2 = bad usage/environment.
#
# Output: a JSON object on stdout. See docs/harness/implement-evidence-schema.md.

set -euo pipefail

WORKTREE=""
BASE_REF=""
ISSUE_JSON=""
PHASES_FILE=""
BUDGET_FILE=""
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
    --budget) BUDGET_FILE="${2:-}"; shift 2 ;;
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
    # vitest.config.mts sets passWithNoTests, so a test path no project picks up
    # exits 0. That is a check that did not run, not one that passed.
    if [[ $exit_code -eq 0 ]] && grep -q "No test files found" "$log"; then
      exit_code="null"
    fi
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

# --- declared verification ---------------------------------------------------
# Phase 2 lists the commands that verify its slices in the first fenced block
# under `## Verification` in implementation.md. They are the agent's words, so
# each is held to an allowlist and, if accepted, run as an argv — never through
# a shell — so nothing in a line can expand, redirect or chain.

# Print why a command is not allowed, or nothing if it is. The one shape allowed
# is `yarn test <path>…`: a declared turbo filter could name a package with no
# type-check task, which turbo reports as a pass.
allowlist_reason() {
  [[ $# -ge 3 && "$1" == "yarn" && "$2" == "test" ]] \
    || { echo "only \`yarn test <path>\` is allowed"; return; }
  shift 2
  local path
  for path in "$@"; do
    if [[ ! "$path" =~ ^[A-Za-z0-9_@./-]+$ ]]; then
      echo "\`$path\` has characters a test path does not"; return
    elif [[ "$path" == -* || "$path" == /* ]]; then
      echo "\`$path\` is a flag or an absolute path"; return
    elif [[ "/$path/" == */../* ]]; then
      echo "\`$path\` leaves the worktree"; return
    elif [[ ! "$path" =~ \.test\.tsx?$ ]]; then
      echo "\`$path\` is not a .test.ts or .test.tsx file"; return
    fi
  done
}

DECLARED_COMMANDS="null"
REJECTED_COMMANDS="[]"
DECLARED_ARGVS=()
PLAN_FILE="$WORKTREE/$SPEC/implementation.md"
if [[ -n "$SPEC" && -f "$PLAN_FILE" ]]; then
  accepted=()
  rejected=()
  while IFS= read -r line; do
    line="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    read -ra words <<<"$line"
    line="${words[*]}"
    printf '%s\n' ${accepted[@]+"${accepted[@]}"} | grep -qxF -- "$line" && continue
    reason="$(allowlist_reason "${words[@]}")"
    if [[ -z "$reason" ]]; then
      accepted+=("$line")
    else
      rejected+=("$(jq -nc --arg command "$line" --arg reason "$reason" '{command: $command, reason: $reason}')")
    fi
  done < <(awk '
    /^## Verification[[:space:]]*$/ { in_section = 1; next }
    in_section && /^## /            { exit }
    in_section && !in_block && /^```/ { in_block = 1; next }
    in_block && /^```/              { exit }
    in_block                        { print }' "$PLAN_FILE")

  # A section that declares nothing at all stays null: there is nothing to say
  # these changes were verified beyond the always-on checks.
  if [[ ${#accepted[@]} -gt 0 || ${#rejected[@]} -gt 0 ]]; then
    DECLARED_COMMANDS="$(printf '%s\n' ${accepted[@]+"${accepted[@]}"} | jq -R . | jq -sc 'map(select(. != ""))')"
    REJECTED_COMMANDS="$(printf '%s\n' ${rejected[@]+"${rejected[@]}"} | jq -sc .)"
    DECLARED_ARGVS=(${accepted[@]+"${accepted[@]}"})
  fi
fi

# The caps the harness ran under and what the phases spent against them.
BUDGET="null"
if [[ -f "$BUDGET_FILE" ]] && jq -e 'type == "object"' "$BUDGET_FILE" >/dev/null 2>&1; then
  BUDGET="$(jq -c --argjson phases "$PHASES" '. + {spent_usd: (($phases // []) | map(.cost_usd // 0) | add // 0)}' "$BUDGET_FILE")"
fi

# Declared runs also write vitest's JSON report, one per command, which is what
# acceptance criteria are judged against: an exit code cannot see a skipped test.
REPORT_DIR="$(mktemp -d)"
trap 'rm -rf "$REPORT_DIR"' EXIT

CHECKS="$(
  {
    report=0
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
    for line in ${DECLARED_ARGVS[@]+"${DECLARED_ARGVS[@]}"}; do
      read -ra words <<<"$line"
      paths=("${words[@]:2}")
      name="test: ${paths[0]}"
      [[ ${#paths[@]} -gt 1 ]] && name+=" (+$((${#paths[@]} - 1)))"
      missing=""
      for path in "${paths[@]}"; do
        [[ -f "$WORKTREE/$path" ]] || { missing="$path"; break; }
      done
      if [[ -n "$missing" ]]; then
        # Never run: vitest would pass a path that matches nothing.
        jq -n --arg name "$name" --arg command "$line" --arg missing "$missing" \
          '{name: $name, command: $command, source: "declared", exit_code: null,
            log_tail: "not run: \($missing) does not exist"}'
      else
        report=$((report + 1))
        run_check "$name" declared "${words[@]}" \
          --reporter=default --reporter=json "--outputFile.json=$REPORT_DIR/$report.json"
      fi
    done
  } | jq -s .
)"

# --- acceptance criteria -----------------------------------------------------
# Each item under `## Acceptance Criteria` in design.md, matched by file and
# vitest full name against the declared runs' reports. A name that matches more
# than one test only counts as passed if all of them did.
CRITERIA="null"
DESIGN_FILE="$WORKTREE/$SPEC/design.md"
if [[ -n "$SPEC" && -f "$DESIGN_FILE" ]]; then
  ITEMS="$(awk '
    /^## Acceptance Criteria[[:space:]]*$/ { in_section = 1; next }
    in_section && /^## /                  { exit }
    in_section && /^- \[[ xX]\] /         { print }' "$DESIGN_FILE" | jq -R . | jq -sc .)"
  if [[ "$(jq 'length' <<<"$ITEMS")" -gt 0 ]]; then
    # vitest names files by absolute path, which may be the resolved one.
    RESULTS="$(
      for f in "$REPORT_DIR"/*.json; do
        # A run that crashed before reporting leaves no file, or a broken one;
        # its tests are then simply not found.
        if [[ -f "$f" ]]; then
          jq -c '[.testResults[]? | .name as $file | .assertionResults[]? | {file: $file, name: .fullName, status}]' "$f" 2>/dev/null || true
        fi
      done | jq -sc --arg wt "$WORKTREE/" --arg real "$(cd "$WORKTREE" && pwd -P)/" \
        'add // [] | map(.file |= (ltrimstr($real) | ltrimstr($wt)))'
    )"
    DECLARED_PATHS="$(jq -c '[(. // [])[] | split(" ") | .[2:][]]' <<<"$DECLARED_COMMANDS")"
    CRITERIA="$(jq -c --argjson results "$RESULTS" --argjson declared "$DECLARED_PATHS" '
      map(sub("^- \\[[ xX]\\] "; "")
        | (capture("^(?<text>.*) — `(?<file>[^`]+)` › (?<name>.+)$") // {text: ., file: null, name: null})
        | (.text |= gsub("^\\s+|\\s+$"; "")) | (.name |= (if . then gsub("^\\s+|\\s+$"; "") else . end))
        | . as $c
        | [$results[] | select(.file == $c.file and .name == $c.name) | .status] as $hits
        | {text: .text, test_file: .file, test_name: .name,
           test_found: ($hits | length > 0),
           test_status: (if ($hits | length) == 0 then null
                         elif all($hits[]; . == "passed") then "passed"
                         else first($hits[] | select(. != "passed")) end),
           declared: ($c.file != null and any($declared[]; . == $c.file))})' <<<"$ITEMS")"
  fi
fi

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
  --argjson declared_commands "$DECLARED_COMMANDS" \
  --argjson rejected_commands "$REJECTED_COMMANDS" \
  --argjson criteria "$CRITERIA" \
  --argjson budget "$BUDGET" \
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
    budget: $budget,
    diff: $diff,
    checks: $checks,
    declared_commands: $declared_commands,
    rejected_commands: $rejected_commands,
    criteria: $criteria
  }'
