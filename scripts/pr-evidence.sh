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

# Read a file at a git revision; empty output means the file is absent there.
# Objects are fetched on demand so this works without a full local clone.
blob_at() {
  local rev="$1" path="$2"
  git -C "$REPO_ROOT" show "$rev:$path" 2>/dev/null || true
}

git -C "$REPO_ROOT" fetch --quiet origin "$HEAD_SHA" "$BASE_REF" 2>/dev/null || true
MERGE_BASE="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_REF" "$HEAD_SHA" 2>/dev/null || echo "")"

# Unreachable evidence is reported as such, not guessed at. The policy decides
# what an empty merge base means — here it is simply a fact about the world.
EN_BEFORE="null"
if [[ -n "$MERGE_BASE" ]]; then
  en_raw="$(blob_at "$MERGE_BASE" "$SOURCE_LOCALE")"
  if [[ -n "$en_raw" ]] && jq -e . >/dev/null 2>&1 <<<"$en_raw"; then
    EN_BEFORE="$en_raw"
  fi
fi

# One entry per changed translation file, carrying both sides of the diff.
# `parsed` records whether each side is valid JSON so the policy can tell a
# malformed file from an absent one without re-parsing.
LOCALES="[]"
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  # shellcheck disable=SC2053 — glob matching is the intent.
  [[ "$path" == $LOCALE_GLOB ]] || continue
  [[ "$path" == "$SOURCE_LOCALE" ]] && continue

  after_raw="$(blob_at "$HEAD_SHA" "$path")"
  before_raw=""
  [[ -n "$MERGE_BASE" ]] && before_raw="$(blob_at "$MERGE_BASE" "$path")"

  after_json="null"; after_ok=false
  if [[ -n "$after_raw" ]] && jq -e . >/dev/null 2>&1 <<<"$after_raw"; then
    after_json="$after_raw"; after_ok=true
  fi

  before_json="null"; before_ok=false
  if [[ -n "$before_raw" ]] && jq -e . >/dev/null 2>&1 <<<"$before_raw"; then
    before_json="$before_raw"; before_ok=true
  fi

  LOCALES="$(jq -n \
    --argjson acc "$LOCALES" \
    --arg path "$path" \
    --arg locale "$(basename "$(dirname "$path")")" \
    --argjson after "$after_json" \
    --argjson before "$before_json" \
    --argjson after_parsed "$after_ok" \
    --argjson before_parsed "$before_ok" \
    --argjson after_present "$([[ -n "$after_raw" ]] && echo true || echo false)" \
    '$acc + [{path: $path, locale: $locale,
              after: $after, before: $before,
              after_present: $after_present,
              after_parsed: $after_parsed, before_parsed: $before_parsed}]')"
done <<<"$CHANGED_FILES"

jq -n \
  --argjson pr "$PR_JSON" \
  --argjson locales "$LOCALES" \
  --argjson en_before "$EN_BEFORE" \
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
      number: $pr.number,
      url: $pr.url,
      title: $pr.title,
      author: ($pr.author.login // ""),
      is_draft: $pr.isDraft,
      head_sha: $pr.headRefOid,
      base_ref: $pr.baseRefName,
      changed_files: [$pr.files[].path],
      changes_requested: ([$pr.reviews[]? | select(.state == "CHANGES_REQUESTED")] | length),
      # A CheckRun reports .conclusion once finished and .status while running;
      # a StatusContext reports .state. An unfinished run must not normalise to
      # an empty string, or the policy reports a blank reason.
      checks: [$pr.statusCheckRollup[]?
               | select(.__typename == "CheckRun" or .__typename == "StatusContext")
               | {name: (.name // .context // "check"),
                  state: ((.conclusion // .state // .status // "PENDING")
                          | if . == "" then "PENDING" else . end
                          | ascii_upcase)}]
    },
    en_before: $en_before,
    locales: $locales
  }'
