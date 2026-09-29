#!/usr/bin/env bash
# Decide whether a translation pull request may be merged without a human
# reading the diff.
#
# Implements docs/harness/pr-self-approval-policy.md. Every gate there has a
# check here, and the verdict is the AND of all of them.
#
# Usage:
#   ./scripts/pr-self-approval.sh 12            # a PR in the current repo
#   ./scripts/pr-self-approval.sh --json 12     # machine-readable verdict
#   ./scripts/pr-self-approval.sh               # the PR for the current branch
#
# Exit codes: 0 = auto-approve, 1 = needs-human, 2 = bad usage/environment.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCALE_GLOB="packages/i18n/locales/*/common.json"
SOURCE_LOCALE="packages/i18n/locales/en/common.json"
# Accounts whose translation PRs may self-approve. Add a contributor here when
# they get write access; anyone outside the set is read by a human.
TRUSTED_AUTHORS="${PR_SELF_APPROVAL_AUTHORS:-fernandodof}"
# The lingo.dev workflow commits through a GitHub App, which shows up as a bot.
BOT_AUTHORS="${PR_SELF_APPROVAL_BOTS:-lingo-dot-dev[bot] github-actions[bot] app/cal-com}"
JSON_OUT=false
PR_REF=""

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUT=true; shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "pr-self-approval: unknown option $1" >&2; usage ;;
    *) PR_REF="$1"; shift ;;
  esac
done

for cmd in gh jq git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "pr-self-approval: \`$cmd\` is not on PATH" >&2
    exit 2
  }
done

PR_JSON="$(gh pr view ${PR_REF:+"$PR_REF"} \
  --json number,url,title,author,isDraft,headRefOid,baseRefName,files,reviews,statusCheckRollup \
  2>/dev/null)" || {
  echo "pr-self-approval: could not read PR '${PR_REF:-current branch}' (not found, or gh is not authenticated)" >&2
  exit 2
}

PR_NUMBER="$(jq -r '.number' <<<"$PR_JSON")"
PR_URL="$(jq -r '.url' <<<"$PR_JSON")"
PR_AUTHOR="$(jq -r '.author.login // ""' <<<"$PR_JSON")"
IS_DRAFT="$(jq -r '.isDraft' <<<"$PR_JSON")"
HEAD_SHA="$(jq -r '.headRefOid' <<<"$PR_JSON")"
BASE_REF="$(jq -r '.baseRefName' <<<"$PR_JSON")"
CHANGED_FILES="$(jq -r '.files[].path' <<<"$PR_JSON")"

FAILURES=()
fail() { FAILURES+=("$1"); }

# Read a file at a git revision; empty output means the file is absent there.
# Objects are fetched on demand so the check works without a full local clone.
blob_at() {
  local rev="$1" path="$2"
  git -C "$REPO_ROOT" show "$rev:$path" 2>/dev/null || true
}

# --- Gate 1: translation-only diff ------------------------------------------
non_translation=()
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  # shellcheck disable=SC2053 — glob matching is the intent.
  [[ "$path" == $LOCALE_GLOB ]] || non_translation+=("$path")
done <<<"$CHANGED_FILES"

if [[ ${#non_translation[@]} -gt 0 ]]; then
  fail "scope: ${#non_translation[@]} non-translation file(s) changed ($(IFS=', '; echo "${non_translation[*]:0:5}"))"
fi

# --- Gate 2: en is not modified ---------------------------------------------
if grep -qxF "$SOURCE_LOCALE" <<<"$CHANGED_FILES"; then
  fail "source of truth: $SOURCE_LOCALE was modified"
fi

# Make sure the revisions the later gates diff against are present locally.
git -C "$REPO_ROOT" fetch --quiet origin "$HEAD_SHA" "$BASE_REF" 2>/dev/null || true
MERGE_BASE="$(git -C "$REPO_ROOT" merge-base "origin/$BASE_REF" "$HEAD_SHA" 2>/dev/null || echo "")"

if [[ -z "$MERGE_BASE" ]]; then
  fail "evidence: could not resolve the merge base for $BASE_REF..$HEAD_SHA locally"
fi

# `en` at the merge base is the key and placeholder reference for every locale.
EN_JSON=""
if [[ -n "$MERGE_BASE" ]]; then
  EN_JSON="$(blob_at "$MERGE_BASE" "$SOURCE_LOCALE")"
  [[ -n "$EN_JSON" ]] || fail "evidence: $SOURCE_LOCALE is unreadable at the merge base"
fi

# Gates 3-5 need the file contents on both sides, so they share one pass over
# the changed translation files.
for path in $CHANGED_FILES; do
  # shellcheck disable=SC2053
  [[ "$path" == $LOCALE_GLOB ]] || continue
  [[ "$path" == "$SOURCE_LOCALE" ]] && continue
  [[ -n "$MERGE_BASE" && -n "$EN_JSON" ]] || continue

  locale="$(basename "$(dirname "$path")")"
  after="$(blob_at "$HEAD_SHA" "$path")"
  before="$(blob_at "$MERGE_BASE" "$path")"

  # --- Gate 3: valid JSON, string-shaped ------------------------------------
  if ! jq -e . >/dev/null 2>&1 <<<"$after"; then
    fail "$locale: not valid JSON at the head commit"
    continue
  fi

  # Every leaf must be a string: numbers, booleans and nulls are caught as
  # non-string scalars, arrays as containers that hold no leaf of their own.
  bad_shape="$(jq -r '
    ([paths(scalars) as $p | getpath($p) | select(type != "string")] | length)
    + ([paths as $p | getpath($p) | select(type == "array")] | length)' \
    <<<"$after" 2>/dev/null)" || bad_shape=""
  if [[ -z "$bad_shape" ]]; then
    fail "$locale: could not evaluate value shapes at the head commit"
  elif [[ "$bad_shape" -gt 0 ]]; then
    fail "$locale: $bad_shape value(s) are not strings"
  fi

  # --- Gate 4: no deleted keys, no keys absent from en ----------------------
  # Leaf paths are compared, so a key moving between nesting levels counts as
  # both a deletion and an addition, which is what we want a human to look at.
  leaves='[paths(scalars) | map(tostring) | join(".")]'
  after_leaves="$(jq "$leaves" <<<"$after")"
  before_leaves="[]"
  if [[ -n "$before" ]] && jq -e . >/dev/null 2>&1 <<<"$before"; then
    before_leaves="$(jq "$leaves" <<<"$before")"
    deleted="$(jq -n --argjson a "$before_leaves" --argjson b "$after_leaves" '$a - $b | length')"
    [[ "$deleted" -gt 0 ]] && fail "$locale: $deleted key(s) deleted"
  fi

  # Only keys this PR *introduces* are held against it. A locale that already
  # carried keys `en` lacks is pre-existing drift, not this PR's doing, and
  # failing every translation PR for it would make the gate pure noise.
  orphaned="$(jq -n --argjson locale "$after_leaves" \
                    --argjson prior "$before_leaves" \
                    --argjson en "$(jq "$leaves" <<<"$EN_JSON")" \
                    '(($locale - $en) - ($prior - $en)) | length')"
  [[ "$orphaned" -gt 0 ]] && fail "$locale: $orphaned new key(s) not present in en"

  # --- Gate 5: interpolation placeholders survive ---------------------------
  # For every key the locale shares with en, the set of interpolated variable
  # names must match. Names are compared rather than raw syntax because a
  # locale may legitimately restate a {{count}} as an ICU plural
  # ({count, plural, one {...} other {...}}) — same variable, different form.
  #
  # As with gate 4, only mismatches this PR introduces count: the repo already
  # carries placeholder drift, and a PR that does not touch those keys is not
  # answerable for it.
  mismatch_query='
    def leafmap: [paths(scalars) as $p | {key: ($p | map(tostring) | join(".")), value: getpath($p)}] | from_entries;
    def vars:
      if type != "string" then ["<non-string>"]
      else [scan("\\{\\{\\s*([^}]+?)\\s*\\}\\}") | .[0]]
           + [scan("\\{\\s*([A-Za-z0-9_]+)\\s*,\\s*(?:plural|select|selectordinal)\\b") | .[0]]
           | sort | unique
      end;
    ($en | leafmap) as $E | ($tr | leafmap) as $T
    | [$T | to_entries[]
       | select($E[.key] != null)
       | select(($E[.key] | vars) != (.value | vars))
       | .key] | sort'

  after_bad="$(jq -n --argjson en "$EN_JSON" --argjson tr "$after" "$mismatch_query" 2>/dev/null)" || after_bad=""
  before_bad="[]"
  if [[ -n "$before" ]] && jq -e . >/dev/null 2>&1 <<<"$before"; then
    before_bad="$(jq -n --argjson en "$EN_JSON" --argjson tr "$before" "$mismatch_query" 2>/dev/null)" || before_bad="[]"
  fi

  if [[ -z "$after_bad" ]]; then
    fail "$locale: could not evaluate placeholders at the head commit"
  else
    dropped="$(jq -n --argjson a "$after_bad" --argjson b "$before_bad" '$a - $b | length')"
    [[ "${dropped:-0}" -gt 0 ]] && fail "$locale: $dropped key(s) newly mismatch their {{placeholders}}"
  fi

done

# --- Gate 6: CI is green ----------------------------------------------------
CHECK_SUMMARY="$(jq -r '
  [.statusCheckRollup[]?
   | select(.__typename == "CheckRun" or .__typename == "StatusContext")
   | {name: (.name // .context // "check"),
      state: (.conclusion // .state // "PENDING" | ascii_upcase)}]
  | if length == 0 then "none"
    else (map(select(.state != "SUCCESS" and .state != "NEUTRAL" and .state != "SKIPPED"))
          | if length == 0 then "green"
            else map("\(.name)=\(.state)") | join(", ")
            end)
    end' <<<"$PR_JSON")"

case "$CHECK_SUMMARY" in
  green) ;;
  none)  fail "CI: no checks have reported on the head commit" ;;
  *)     fail "CI: not green ($CHECK_SUMMARY)" ;;
esac

# --- Gate 7: not a draft, no requested changes ------------------------------
[[ "$IS_DRAFT" == "true" ]] && fail "state: the PR is a draft"

CHANGES_REQUESTED="$(jq -r '[.reviews[]? | select(.state == "CHANGES_REQUESTED")] | length' <<<"$PR_JSON")"
[[ "$CHANGES_REQUESTED" -gt 0 ]] && fail "review: $CHANGES_REQUESTED review(s) requested changes"

# --- Gate 8: author is a trusted committer or the translation bot -----------
author_allowed=false
for account in $TRUSTED_AUTHORS $BOT_AUTHORS; do
  [[ "$PR_AUTHOR" == "$account" ]] && author_allowed=true
done
[[ "$author_allowed" == true ]] || fail "author: '$PR_AUTHOR' is not a trusted committer or known translation bot"

# --- Verdict ----------------------------------------------------------------
LOCALE_COUNT="$(grep -c . <<<"$CHANGED_FILES" || true)"

if [[ ${#FAILURES[@]} -eq 0 ]]; then
  VERDICT="auto-approve"
  EXIT_CODE=0
else
  VERDICT="needs-human"
  EXIT_CODE=1
fi

if [[ "$JSON_OUT" == true ]]; then
  printf '%s\n' "${FAILURES[@]+"${FAILURES[@]}"}" | jq -R . | jq -s \
    --arg verdict "$VERDICT" \
    --arg url "$PR_URL" \
    --arg author "$PR_AUTHOR" \
    --argjson pr "$PR_NUMBER" \
    --argjson files "$LOCALE_COUNT" \
    'map(select(. != "")) as $reasons
     | {pr: $pr, url: $url, author: $author, verdict: $verdict,
        changed_files: $files, reasons: $reasons}'
else
  echo "PR #$PR_NUMBER — $VERDICT"
  echo "  $PR_URL"
  echo "  $LOCALE_COUNT changed file(s), author $PR_AUTHOR"
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo "  gates failed:"
    printf '    - %s\n' "${FAILURES[@]}"
  fi
fi

exit $EXIT_CODE
