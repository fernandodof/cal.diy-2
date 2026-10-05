#!/usr/bin/env bash
# Collect the evidence a self-approval decision needs, as one JSON document.
#
# This script knows how to talk to GitHub and git. It does not know the policy:
# it never decides anything, and it emits the same document whether the PR is
# perfect or a disaster. `scripts/pr-self-approval.sh` reads that document and
# applies docs/harness/pr-self-approval-policy.md to it.
#
# Splitting them this way means the policy can be tested against a handwritten
# JSON fixture with no network, and evidence can be gathered somewhere else
# (CI, a cron job) and piped in later.
#
# Usage:
#   ./scripts/pr-evidence.sh 12          # a PR in the current repo
#   ./scripts/pr-evidence.sh             # the PR for the current branch
#
# Exit codes: 0 = evidence collected, 2 = could not collect it.
#
# Output: a JSON object on stdout. See docs/harness/pr-evidence-schema.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCALE_GLOB="packages/i18n/locales/*/common.json"
SOURCE_LOCALE="packages/i18n/locales/en/common.json"
PR_REF=""

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "pr-evidence: unknown option $1" >&2; usage ;;
    *) PR_REF="$1"; shift ;;
  esac
done

for cmd in gh jq git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "pr-evidence: \`$cmd\` is not on PATH" >&2
    exit 2
  }
done

PR_JSON="$(gh pr view ${PR_REF:+"$PR_REF"} \
  --json number,url,title,author,isDraft,headRefOid,baseRefName,files,reviews,statusCheckRollup \
  2>/dev/null)" || {
  echo "pr-evidence: could not read PR '${PR_REF:-current branch}' (not found, or gh is not authenticated)" >&2
  exit 2
}

HEAD_SHA="$(jq -r '.headRefOid' <<<"$PR_JSON")"
BASE_REF="$(jq -r '.baseRefName' <<<"$PR_JSON")"
CHANGED_FILES="$(jq -r '.files[].path' <<<"$PR_JSON")"

# Locale files run to hundreds of KB, and a 44-locale PR would exceed ARG_MAX
# if their contents were passed to jq as arguments. Everything large goes
# through files on disk instead of argv.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Write a file at a git revision to $TMP_DIR/$2 and echo "ok" when it exists and
# parses as JSON, "malformed" when it exists but does not, "absent" otherwise.
# Objects are fetched on demand so this works without a full local clone.
blob_to() {
  local rev="$1" path="$2" dest="$TMP_DIR/$3"
  if ! git -C "$REPO_ROOT" show "$rev:$path" > "$dest" 2>/dev/null; then
    : > "$dest"
    echo "absent"; return
  fi
  [[ -s "$dest" ]] || { echo "absent"; return; }
  if jq -e . >/dev/null 2>&1 < "$dest"; then echo "ok"; else echo "malformed"; fi
}

git -C "$REPO_ROOT" fetch --quiet origin "$HEAD_SHA" "$BASE_REF" 2>/dev/null || true
MERGE_BASE="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_REF" "$HEAD_SHA" 2>/dev/null || echo "")"

# Unreachable evidence is reported as such, not guessed at. The policy decides
# what an empty merge base means — here it is simply a fact about the world.
echo "null" > "$TMP_DIR/en_before.json"
if [[ -n "$MERGE_BASE" ]]; then
  if [[ "$(blob_to "$MERGE_BASE" "$SOURCE_LOCALE" "en_candidate.json")" == "ok" ]]; then
    mv "$TMP_DIR/en_candidate.json" "$TMP_DIR/en_before.json"
  fi
fi

# One entry per changed translation file, carrying both sides of the diff.
# `parsed` records whether each side is valid JSON so the policy can tell a
# malformed file from an absent one without re-parsing.
entry_count=0
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  # shellcheck disable=SC2053 — glob matching is the intent.
  [[ "$path" == $LOCALE_GLOB ]] || continue
  [[ "$path" == "$SOURCE_LOCALE" ]] && continue

  after_state="$(blob_to "$HEAD_SHA" "$path" "after.json")"
  before_state="absent"
  [[ -n "$MERGE_BASE" ]] && before_state="$(blob_to "$MERGE_BASE" "$path" "before.json")"

  # A blob that is absent or malformed is recorded as null; the flags say which,
  # so the policy can tell "missing at head" from "there but unparseable".
  [[ "$after_state" == "ok" ]]  || echo "null" > "$TMP_DIR/after.json"
  [[ "$before_state" == "ok" ]] || echo "null" > "$TMP_DIR/before.json"

  jq -n \
    --slurpfile after "$TMP_DIR/after.json" \
    --slurpfile before "$TMP_DIR/before.json" \
    --arg path "$path" \
    --arg locale "$(basename "$(dirname "$path")")" \
    --argjson after_present "$([[ "$after_state" != "absent" ]] && echo true || echo false)" \
    --argjson after_parsed "$([[ "$after_state" == "ok" ]] && echo true || echo false)" \
    --argjson before_parsed "$([[ "$before_state" == "ok" ]] && echo true || echo false)" \
    '{path: $path, locale: $locale,
      after: $after[0], before: $before[0],
      after_present: $after_present,
      after_parsed: $after_parsed, before_parsed: $before_parsed}' \
    > "$TMP_DIR/entry-$entry_count.json"
  entry_count=$((entry_count + 1))
done <<<"$CHANGED_FILES"

# Collect the per-locale entries into one array without passing them as args.
if [[ $entry_count -gt 0 ]]; then
  jq -s . "$TMP_DIR"/entry-*.json > "$TMP_DIR/locales.json"
else
  echo "[]" > "$TMP_DIR/locales.json"
fi

printf '%s' "$PR_JSON" > "$TMP_DIR/pr.json"

jq -n \
  --slurpfile pr "$TMP_DIR/pr.json" \
  --slurpfile locales "$TMP_DIR/locales.json" \
  --slurpfile en_before "$TMP_DIR/en_before.json" \
  --arg merge_base "$MERGE_BASE" \
  --arg source_locale "$SOURCE_LOCALE" \
  --arg locale_glob "$LOCALE_GLOB" \
  --arg collected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    schema: "pr-evidence/1",
    collected_at: $collected_at,
    source_locale: $source_locale,
    locale_glob: $locale_glob,
    merge_base: (if $merge_base == "" then null else $merge_base end),
    pr: {
      number: $pr[0].number,
      url: $pr[0].url,
      title: $pr[0].title,
      author: ($pr[0].author.login // ""),
      is_draft: $pr[0].isDraft,
      head_sha: $pr[0].headRefOid,
      base_ref: $pr[0].baseRefName,
      changed_files: [$pr[0].files[].path],
      changes_requested: ([$pr[0].reviews[]? | select(.state == "CHANGES_REQUESTED")] | length),
      # A CheckRun reports .conclusion once finished and .status while running;
      # a StatusContext reports .state. An unfinished run must not normalise to
      # an empty string, or the policy reports a blank reason.
      checks: [$pr[0].statusCheckRollup[]?
               | select(.__typename == "CheckRun" or .__typename == "StatusContext")
               | {name: (.name // .context // "check"),
                  state: ((.conclusion // .state // .status // "PENDING")
                          | if . == "" then "PENDING" else . end
                          | ascii_upcase)}]
    },
    en_before: $en_before[0],
    locales: $locales[0]
  }'
