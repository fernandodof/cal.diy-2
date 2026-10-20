#!/usr/bin/env bash
# Score every case in the eval set and compare the judge against the human scores.
#
#   ./run.sh                 score every case with a human_score set
#   JUDGE_MODEL=claude-opus-5 ./run.sh
#
# Cases with a blank human_score are skipped: an unscored case has nothing to
# compare against. Set it in the case frontmatter first.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
out="$HERE/runs/$stamp.json"
mkdir -p "$HERE/runs"

shopt -s nullglob
cases=("$HERE"/cases/*.md)
(( ${#cases[@]} )) || { echo "no cases in $HERE/cases — run ./snapshot.sh <issue> first" >&2; exit 1; }

results=(); skipped=()
for f in "${cases[@]}"; do
  human=$(sed -n 's/^human_score: *//p' "$f" | head -1 | tr -d ' ')
  if [ -z "$human" ]; then skipped+=("$(basename "$f")"); continue; fi
  judged=$("$HERE/score.sh" "$f")
  results+=("$(printf '%s' "$judged" | jq -c --argjson h "$human" \
    '. + {human: $h, delta: (if .score == null then null else (.score - $h) end)}')")
  printf '.' >&2
done
printf '\n' >&2

if (( ${#skipped[@]} )); then
  printf 'skipped (no human_score): %s\n\n' "${skipped[*]}" >&2
fi
(( ${#results[@]} )) || { echo "nothing scored — every case is missing a human_score" >&2; exit 1; }

printf '%s\n' "${results[@]}" | jq -s --arg ts "$stamp" --arg model "${JUDGE_MODEL:-claude-haiku-4-5-20251001}" '{
  run: $ts, model: $model, cases: .,
  summary: {
    n: length,
    exact: [.[] | select(.delta == 0)] | length,
    within_1: [.[] | select(.delta != null and (.delta | fabs) <= 1)] | length,
    parse_failures: [.[] | select(.score == null)] | length,
    mean_abs_error: ([.[] | select(.delta != null) | .delta | fabs] | if length == 0 then null else (add / length) end)
  }
}' > "$out"

echo "run: $out"
echo
printf '%-22s %6s %6s %6s\n' "CASE" "HUMAN" "JUDGE" "DELTA"
jq -r '.cases[] | [.id, (.human|tostring), (.score|tostring),
       (if .delta == null then "-" else (if .delta > 0 then "+" else "" end) + (.delta|tostring) end)] | @tsv' "$out" \
  | awk -F'\t' '{printf "%-22s %6s %6s %6s\n", $1, $2, $3, $4}'
echo
jq -r '.summary | "exact: \(.exact)/\(.n)   within 1: \(.within_1)/\(.n)   mean abs error: \(.mean_abs_error)   parse failures: \(.parse_failures)"' "$out"
echo
echo "reasoning:"
jq -r '.cases[] | "  \(.id): \(.reasoning)"' "$out"
