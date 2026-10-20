#!/usr/bin/env bash
# Freeze a GitHub issue into the eval set as a case file.
#
#   ./snapshot.sh 19                     snapshot from the default repo
#   ./snapshot.sh calcom/cal.com#30300   snapshot from any repo
#
# Writes cases/<id>.md with a title/link/score header over the frozen body.
# Re-snapshotting an issue whose body changed writes a NEW version (.v2, .v3 ...)
# instead of overwriting: the old row stays comparable, and the score delta
# between versions shows what the author's update bought.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="${EVAL_REPO:-fernandodof/cal.diy-2}"
ref="${1:?usage: snapshot.sh <issue-number | owner/repo#number>}"

if [[ "$ref" == *#* ]]; then repo="${ref%%#*}"; num="${ref##*#}"; else repo="$DEFAULT_REPO"; num="$ref"; fi

meta=$(gh issue view "$num" --repo "$repo" --json title,body,url)
title=$(printf '%s' "$meta" | jq -r '.title')
url=$(printf '%s' "$meta" | jq -r '.url')
body=$(printf '%s' "$meta" | jq -r '.body')

slug="issue-$num"
[ "$repo" = "$DEFAULT_REPO" ] || slug="$(printf '%s' "$repo" | tr '/' '-')-$num"

mkdir -p "$HERE/cases"
base="$HERE/cases/$slug"
target="$base.md"

# If a snapshot exists, compare bodies. Identical -> nothing to do.
# Changed -> next version alongside it, so both stay scoreable.
if [ -f "$target" ]; then
  # Compare with trailing blank lines normalised: gh and the file differ by a
  # trailing newline, which is not an author edit.
  existing=$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; rest=1; next} rest' "$target" \
             | sed -e 's/\r$//' | awk 'BEGIN{RS="\0"} {sub(/\n+$/,""); print}')
  norm_body=$(printf '%s' "$body" | sed -e 's/\r$//' | awk 'BEGIN{RS="\0"} {sub(/\n+$/,""); print}')
  if [ "$existing" = "$norm_body" ]; then
    echo "unchanged: $target"; exit 0
  fi
  v=2
  while [ -f "$base.v$v.md" ]; do v=$((v+1)); done
  prev="$target"
  for ((i=2; i<v; i++)); do prev="$base.v$i.md"; done
  target="$base.v$v.md"; slug="$slug.v$v"
  echo "body changed since $prev -> new version" >&2
fi

{
  printf -- "---\nid: %s\ntitle: %s\nlink: %s\nhuman_score: \nsnapshot: %s\n---\n\n" \
    "$slug" "$title" "$url" "$(date -u +%Y-%m-%d)"
  printf '%s\n' "$body"
} > "$target"

echo "$target"
echo "  -> set human_score in the frontmatter before running ./run.sh" >&2
