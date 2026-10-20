#!/usr/bin/env bash
# Score a GitHub issue for ambiguity (0-3) with an LLM judge.
#
#   ./score.sh cases/issue-19.md        score a frozen snapshot from the eval set
#   ./score.sh --issue 19               score a live issue (fetches, stores nothing)
#   ./score.sh --issue calcom/cal.com#30300
#
# Prints one JSON object: {"id","score","reasoning"}
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${JUDGE_MODEL:-claude-haiku-4-5-20251001}"
DEFAULT_REPO="${EVAL_REPO:-fernandodof/cal.diy-2}"

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }
[ $# -gt 0 ] || usage

if [ "$1" = "--issue" ]; then
  ref="${2:?--issue needs an issue number or owner/repo#number}"
  if [[ "$ref" == *#* ]]; then repo="${ref%%#*}"; num="${ref##*#}"; else repo="$DEFAULT_REPO"; num="$ref"; fi
  id="$repo#$num"
  issue=$(gh issue view "$num" --repo "$repo" --json title,body --jq '"\(.title)\n\n\(.body)"')
else
  CASE_FILE="$1"
  [ -f "$CASE_FILE" ] || { echo "no such case file: $CASE_FILE" >&2; exit 1; }
  id=$(sed -n 's/^id: *//p' "$CASE_FILE" | head -1)
  title=$(sed -n 's/^title: *//p' "$CASE_FILE" | head -1)
  # Body is everything after the frontmatter. The judge must never see human_score.
  body=$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; rest=1; next} rest' "$CASE_FILE")
  issue=$(printf '%s\n\n%s' "$title" "$body")
fi

prompt=$(cat <<EOF
You are scoring a GitHub issue for ambiguity using the rubric below.

$(cat "$HERE/RUBRIC.md")

---

Here is the issue to score:

<issue>
$issue
</issue>

Reply with ONLY a JSON object, no prose and no markdown fences:
{"score": <0-3 integer>, "reasoning": "<one sentence citing what the issue does or does not pin down>"}
EOF
)

raw=$(claude -p "$prompt" --output-format json --model "$MODEL" \
      --allowed-tools "" 2>/dev/null | jq -r '.result')

# The model may wrap JSON in ``` fences despite instructions; strip them.
clean=$(printf '%s' "$raw" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//' | tr -d '\000')

if ! printf '%s' "$clean" | jq -e '.score' >/dev/null 2>&1; then
  printf '{"id":"%s","score":null,"reasoning":"PARSE_FAILURE","raw":%s}\n' \
    "$id" "$(printf '%s' "$raw" | jq -Rs .)"
  exit 0
fi

printf '%s' "$clean" | jq -c --arg id "$id" '{id: $id, score: .score, reasoning: .reasoning}'
