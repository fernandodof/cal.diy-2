#!/usr/bin/env bash
# Decide whether a translation pull request may be merged without a human
# reading the diff.
#
# Implements docs/harness/pr-self-approval-policy.md. Every gate there has a
# check here, and the verdict is the AND of all of them.
#
# This script is pure policy: it reads an evidence document (see
# docs/harness/pr-evidence-schema.md) and never touches the network, GitHub or
# git. `scripts/pr-evidence.sh` produces that document. Keeping the two apart
# means the policy can be tested against a fixture, and the same evidence can
# be judged twice without being gathered twice.
#
# Usage:
#   ./scripts/pr-evidence.sh 12 | ./scripts/pr-self-approval.sh
#   ./scripts/pr-self-approval.sh --evidence evidence.json
#   ./scripts/pr-self-approval.sh --json --evidence evidence.json
#   ./scripts/pr-self-approval.sh 12        # collects evidence first, for convenience
#
# Exit codes: 0 = auto-approve, 1 = needs-human, 2 = bad usage/environment.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Accounts whose translation PRs may self-approve. Add a contributor here when
# they get write access; anyone outside the set is read by a human.
TRUSTED_AUTHORS="${PR_SELF_APPROVAL_AUTHORS:-fernandodof}"
# The lingo.dev workflow commits through a GitHub App, which shows up as a bot.
BOT_AUTHORS="${PR_SELF_APPROVAL_BOTS:-lingo-dot-dev[bot] github-actions[bot] app/cal-com}"
JSON_OUT=false
EVIDENCE_FILE=""
PR_REF=""

usage() {
  sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUT=true; shift ;;
    --evidence) EVIDENCE_FILE="${2:-}"; [[ -n "$EVIDENCE_FILE" ]] || usage; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "pr-self-approval: unknown option $1" >&2; usage ;;
    *) PR_REF="$1"; shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "pr-self-approval: \`jq\` is not on PATH" >&2
  exit 2
}

# Evidence comes from a file, from stdin, or — as a convenience for the common
# case — from the collector, which is the only branch that needs a network.
if [[ -n "$EVIDENCE_FILE" ]]; then
  EVIDENCE="$(cat "$EVIDENCE_FILE")" || exit 2
elif [[ -n "$PR_REF" ]]; then
  EVIDENCE="$("$REPO_ROOT/scripts/pr-evidence.sh" "$PR_REF")" || exit 2
elif [[ ! -t 0 ]]; then
  EVIDENCE="$(cat)"
else
  EVIDENCE="$("$REPO_ROOT/scripts/pr-evidence.sh")" || exit 2
fi

jq -e . >/dev/null 2>&1 <<<"$EVIDENCE" || {
  echo "pr-self-approval: evidence is not valid JSON" >&2
  exit 2
}

SCHEMA="$(jq -r '.schema // ""' <<<"$EVIDENCE")"
[[ "$SCHEMA" == "pr-evidence/1" ]] || {
  echo "pr-self-approval: unsupported evidence schema '${SCHEMA:-none}' (expected pr-evidence/1)" >&2
  exit 2
}

ev() { jq -r "$1" <<<"$EVIDENCE"; }

PR_NUMBER="$(ev '.pr.number')"
PR_URL="$(ev '.pr.url')"
PR_AUTHOR="$(ev '.pr.author')"
IS_DRAFT="$(ev '.pr.is_draft')"
MERGE_BASE="$(ev '.merge_base // ""')"
SOURCE_LOCALE="$(ev '.source_locale')"
LOCALE_GLOB="$(ev '.locale_glob')"
CHANGED_FILES="$(ev '.pr.changed_files[]?')"

FAILURES=()
fail() { FAILURES+=("$1"); }

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

# Evidence the later gates depend on. Missing evidence is a failure, never a
# pass: a gate that could not run has not been satisfied.
EVIDENCE_OK=true
if [[ -z "$MERGE_BASE" ]]; then
  fail "evidence: could not resolve the merge base for $(ev '.pr.base_ref')..$(ev '.pr.head_sha')"
  EVIDENCE_OK=false
fi
if [[ "$(ev '.en_before | type')" != "object" ]]; then
  fail "evidence: $SOURCE_LOCALE is unreadable at the merge base"
  EVIDENCE_OK=false
fi

# --- Gates 3-5: per-locale structural checks --------------------------------
# All three read the same before/after pair, so they share one pass. The jq
# below is the whole of the per-file policy; it takes en and one locale entry
# and returns the reasons that entry fails.
LOCALE_POLICY='
  def leaves: [paths(scalars) | map(tostring) | join(".")];
  def leafmap: [paths(scalars) as $p | {key: ($p | map(tostring) | join(".")), value: getpath($p)}] | from_entries;

  # Interpolated variable names, not raw syntax: a locale may legitimately
  # restate en'"'"'s {{count}} as an ICU plural ({count, plural, one {…} other {…}}).
  def vars:
    if type != "string" then ["<non-string>"]
    else [scan("\\{\\{\\s*([^}]+?)\\s*\\}\\}") | .[0]]
         + [scan("\\{\\s*([A-Za-z0-9_]+)\\s*,\\s*(?:plural|select|selectordinal)\\b") | .[0]]
         | sort | unique
    end;

  def mismatches($en):
    ($en | leafmap) as $E
    | [leafmap | to_entries[]
       | select($E[.key] != null)
       | select(($E[.key] | vars) != (.value | vars))
       | .key] | sort;

  . as {$en, $entry}
  | $entry.locale as $loc
  | if ($entry.after_present | not) then ["\($loc): unreadable at the head commit"]
    elif ($entry.after_parsed | not) then ["\($loc): not valid JSON at the head commit"]
    else
      ($entry.after) as $after
      | ($entry.before) as $before
      | ($entry.before_parsed) as $has_before
      | ($after | leaves) as $after_leaves
      | (if $has_before then ($before | leaves) else [] end) as $before_leaves
      | ($en | leaves) as $en_leaves

      # Gate 3: every leaf is a string, and no value is an array.
      | ([$after | paths(scalars) as $p | getpath($p) | select(type != "string")] | length
         + ([$after | paths as $p | getpath($p) | select(type == "array")] | length)) as $bad_shape

      # Gate 4: nothing deleted; no key introduced that en lacks. Only keys
      # this PR adds are held against it — pre-existing drift belongs to
      # whoever introduced it, not to the next PR that touches the file.
      | (if $has_before then ($before_leaves - $after_leaves | length) else 0 end) as $deleted
      | ((($after_leaves - $en_leaves) - ($before_leaves - $en_leaves)) | length) as $orphaned

      # Gate 5: placeholders survive, again counting only new breakage.
      | ($after | mismatches($en)) as $after_bad
      | (if $has_before then ($before | mismatches($en)) else [] end) as $before_bad
      | (($after_bad - $before_bad) | length) as $dropped

      | [ (if $bad_shape > 0 then "\($loc): \($bad_shape) value(s) are not strings" else empty end),
          (if $deleted   > 0 then "\($loc): \($deleted) key(s) deleted" else empty end),
          (if $orphaned  > 0 then "\($loc): \($orphaned) new key(s) not present in en" else empty end),
          (if $dropped   > 0 then "\($loc): \($dropped) key(s) newly mismatch their {{placeholders}}" else empty end) ]
    end'

if [[ "$EVIDENCE_OK" == true ]]; then
  while IFS= read -r reason; do
    [[ -n "$reason" ]] && fail "$reason"
  done < <(jq -r "[.en_before as \$en | .locales[] | {\$en, entry: .} | ($LOCALE_POLICY)] | flatten | .[]" <<<"$EVIDENCE")
fi

# --- Gate 6: CI is green ----------------------------------------------------
# The enforcing workflow is itself a check on the PR it is judging, so it is
# always PENDING while it runs. Counting it would deadlock every PR: the gate
# could never go green. Its own result is the verdict, not evidence for it.
SELF_CHECK_NAME="${PR_SELF_APPROVAL_SELF_CHECK:-Self-approval check}"

CHECK_SUMMARY="$(jq -r --arg self "$SELF_CHECK_NAME" '
  .pr.checks
  | map(select(.name != $self))
  | if length == 0 then "none"
    else (map(select(.state != "SUCCESS" and .state != "NEUTRAL" and .state != "SKIPPED"))
          | if length == 0 then "green"
            else map("\(.name)=\(.state)") | join(", ")
            end)
    end' <<<"$EVIDENCE")"

case "$CHECK_SUMMARY" in
  green) ;;
  none)  fail "CI: no checks have reported on the head commit" ;;
  *)     fail "CI: not green ($CHECK_SUMMARY)" ;;
esac

# --- Gate 7: not a draft, no requested changes ------------------------------
[[ "$IS_DRAFT" == "true" ]] && fail "state: the PR is a draft"

CHANGES_REQUESTED="$(ev '.pr.changes_requested')"
[[ "$CHANGES_REQUESTED" -gt 0 ]] && fail "review: $CHANGES_REQUESTED review(s) requested changes"

# --- Gate 8: author is a trusted committer or the translation bot -----------
author_allowed=false
for account in $TRUSTED_AUTHORS $BOT_AUTHORS; do
  [[ "$PR_AUTHOR" == "$account" ]] && author_allowed=true
done
[[ "$author_allowed" == true ]] || fail "author: '$PR_AUTHOR' is not a trusted committer or known translation bot"

# --- Verdict ----------------------------------------------------------------
LOCALE_COUNT="$(jq -r '.pr.changed_files | length' <<<"$EVIDENCE")"

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
