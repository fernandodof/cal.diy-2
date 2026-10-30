#!/usr/bin/env bash
# Run a task through Claude Code headlessly and save the result.
#
# Usage:
#   ./scripts/headless-task.sh "add a unit test for getWorkingHours"
#   ./scripts/headless-task.sh --run-id nightly-lint "fix biome warnings in packages/lib"
#   cat task.md | ./scripts/headless-task.sh -
#   ./scripts/headless-task.sh --issue 42
#   ./scripts/headless-task.sh --issue https://github.com/owner/repo/issues/42
#   ./scripts/headless-task.sh --workdir ../worktrees/issue-42 --issue 42
#   ./scripts/headless-task.sh --allowed-tools "Read,Edit,Bash(yarn test:*)" \
#     --disallowed-tools "Bash(git push:*)" "add a unit test for getWorkingHours"
#
# Exit codes: 0 = completed, 1 = agent failed, 2 = bad usage/environment.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${HEADLESS_TASK_OUT_DIR:-$REPO_ROOT/.claude/headless-runs}"
MAX_TURNS="${HEADLESS_TASK_MAX_TURNS:-40}"
PERMISSION_MODE="${HEADLESS_TASK_PERMISSION_MODE:-acceptEdits}"
# Dollars the session may spend; unset means the CLI's own default (none).
MAX_BUDGET_USD="${HEADLESS_TASK_MAX_BUDGET_USD:-}"
WORKDIR="${HEADLESS_TASK_WORKDIR:-}"
# Comma-separated permission rules, passed through to the CLI as given.
ALLOWED_TOOLS="${HEADLESS_TASK_ALLOWED_TOOLS:-}"
DISALLOWED_TOOLS="${HEADLESS_TASK_DISALLOWED_TOOLS:-}"
RUN_ID=""
ISSUE=""

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

# Render a GitHub issue as the task prompt. Accepts a number or a full URL;
# `gh` resolves a bare number against the current repo's remote.
issue_to_task() {
  local ref="$1" json
  command -v gh >/dev/null 2>&1 || {
    echo "headless-task: --issue needs the \`gh\` CLI on PATH" >&2
    exit 2
  }
  json="$(gh issue view "$ref" --json number,title,body,url 2>/dev/null)" || {
    echo "headless-task: could not fetch issue '$ref' (not found, or gh is not authenticated)" >&2
    exit 2
  }
  jq -r '"Implement GitHub issue #\(.number): \(.title)\n\n\(.url)\n\n---\n\n" + (.body // "(no description)")' <<<"$json"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; [[ -n "$ISSUE" ]] || usage; shift 2 ;;
    --run-id) RUN_ID="${2:-}"; [[ -n "$RUN_ID" ]] || usage; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; [[ -n "$WORKDIR" ]] || usage; shift 2 ;;
    --allowed-tools) ALLOWED_TOOLS="${2:-}"; [[ -n "$ALLOWED_TOOLS" ]] || usage; shift 2 ;;
    --disallowed-tools) DISALLOWED_TOOLS="${2:-}"; [[ -n "$DISALLOWED_TOOLS" ]] || usage; shift 2 ;;
    --max-turns) MAX_TURNS="${2:-}"; shift 2 ;;
    --max-budget-usd) MAX_BUDGET_USD="${2:-}"; [[ -n "$MAX_BUDGET_USD" ]] || usage; shift 2 ;;
    --permission-mode) PERMISSION_MODE="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -) break ;;
    -*) echo "headless-task: unknown option $1" >&2; usage ;;
    *) break ;;
  esac
done

if [[ -n "$ISSUE" ]]; then
  TASK="$(issue_to_task "$ISSUE")"
  RUN_ID="${RUN_ID:-issue-${ISSUE##*/}}"
elif [[ "${1:-}" == "-" ]]; then
  TASK="$(cat)"
else
  TASK="${*:-}"
fi

if [[ -z "${TASK// }" ]]; then
  echo "headless-task: a task is required (as an argument or on stdin)" >&2
  usage
fi

command -v claude >/dev/null 2>&1 || {
  echo "headless-task: the \`claude\` CLI is not on PATH" >&2
  exit 2
}

# The session runs in, and may only touch, the working directory: the repo by
# default, or a worktree when a caller isolates the run from this checkout.
if [[ -n "$WORKDIR" ]]; then
  [[ -d "$WORKDIR" ]] || {
    echo "headless-task: --workdir '$WORKDIR' is not a directory" >&2
    exit 2
  }
  WORKDIR="$(cd "$WORKDIR" && pwd)"
else
  WORKDIR="$REPO_ROOT"
fi

RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
RUN_DIR="$OUT_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

printf '%s\n' "$TASK" > "$RUN_DIR/task.txt"

echo "headless-task: run $RUN_ID -> $RUN_DIR" >&2

# A denied rule beats an allowed one, so a caller can rely on --disallowed-tools
# even under a permissive --permission-mode.
TOOL_ARGS=()
[[ -n "$ALLOWED_TOOLS" ]] && TOOL_ARGS+=(--allowedTools "$ALLOWED_TOOLS")
[[ -n "$DISALLOWED_TOOLS" ]] && TOOL_ARGS+=(--disallowedTools "$DISALLOWED_TOOLS")
[[ -n "$MAX_BUDGET_USD" ]] && TOOL_ARGS+=(--max-budget-usd "$MAX_BUDGET_USD")

set +e
printf '%s' "$TASK" | (cd "$WORKDIR" && claude \
  --print \
  --output-format json \
  --permission-mode "$PERMISSION_MODE" \
  --max-turns "$MAX_TURNS" \
  ${TOOL_ARGS[@]+"${TOOL_ARGS[@]}"} \
  --add-dir "$WORKDIR") \
  > "$RUN_DIR/result.json" 2> "$RUN_DIR/stderr.log"
CLI_STATUS=$?
set -e

# The agent reports its own outcome inside the JSON envelope, so a zero exit
# from the CLI is not on its own proof the task completed.
IS_ERROR="$(jq -r 'if type == "object" then (.is_error // false) else false end' "$RUN_DIR/result.json" 2>/dev/null || echo "true")"
SUBTYPE="$(jq -r 'if type == "object" then (.subtype // "unknown") else "unparseable" end' "$RUN_DIR/result.json" 2>/dev/null || echo "unparseable")"

if [[ $CLI_STATUS -eq 0 && "$IS_ERROR" == "false" && "$SUBTYPE" == "success" ]]; then
  STATUS="completed"
  EXIT_CODE=0
else
  STATUS="failed"
  EXIT_CODE=1
fi

jq -r 'if type == "object" then (.result // "") else "" end' "$RUN_DIR/result.json" \
  > "$RUN_DIR/result.md" 2>/dev/null || : > "$RUN_DIR/result.md"

jq -n \
  --arg run_id "$RUN_ID" \
  --arg status "$STATUS" \
  --arg subtype "$SUBTYPE" \
  --arg finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson cli_exit_code "$CLI_STATUS" \
  --argjson turns "$(jq -r 'if type == "object" then (.num_turns // 0) else 0 end' "$RUN_DIR/result.json" 2>/dev/null || echo 0)" \
  --argjson cost_usd "$(jq -r 'if type == "object" then (.total_cost_usd // 0) else 0 end' "$RUN_DIR/result.json" 2>/dev/null || echo 0)" \
  '{run_id: $run_id, status: $status, subtype: $subtype, cli_exit_code: $cli_exit_code, turns: $turns, cost_usd: $cost_usd, finished_at: $finished_at}' \
  > "$RUN_DIR/summary.json"

cat "$RUN_DIR/summary.json" >&2

if [[ "$STATUS" == "completed" ]]; then
  cat "$RUN_DIR/result.md"
else
  echo "headless-task: run $RUN_ID failed ($SUBTYPE, cli exit $CLI_STATUS); see $RUN_DIR/stderr.log" >&2
fi

exit $EXIT_CODE
