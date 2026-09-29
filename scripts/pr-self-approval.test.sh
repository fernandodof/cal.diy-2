#!/usr/bin/env bash
# Gate-logic tests for scripts/pr-self-approval.sh.
#
# The control itself needs a live PR, so these tests exercise the part that can
# be wrong without anyone noticing: the jq that compares two versions of a
# locale file. Each case builds a before/after pair from the real pt-BR file and
# asserts which gate fires.
#
# Usage: ./scripts/pr-self-approval.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EN="$REPO_ROOT/packages/i18n/locales/en/common.json"
BASE="$REPO_ROOT/packages/i18n/locales/pt-BR/common.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ok   $name"
  else
    echo "  FAIL $name: expected $expected, got $actual"
    fails=$((fails + 1))
  fi
}

LEAVES='[paths(scalars) | map(tostring) | join(".")]'
MISMATCH='
  def leafmap: [paths(scalars) as $p | {key: ($p | map(tostring) | join(".")), value: getpath($p)}] | from_entries;
  def vars:
    if type != "string" then ["<non-string>"]
    else [scan("\\{\\{\\s*([^}]+?)\\s*\\}\\}") | .[0]]
         + [scan("\\{\\s*([A-Za-z0-9_]+)\\s*,\\s*(?:plural|select|selectordinal)\\b") | .[0]]
         | sort | unique
    end;
  ($en | leafmap) as $E | ($tr | leafmap) as $T
  | [$T | to_entries[] | select($E[.key] != null)
     | select(($E[.key] | vars) != (.value | vars)) | .key] | sort'

EN_JSON="$(cat "$EN")"
BEFORE="$(cat "$BASE")"
BEFORE_LEAVES="$(jq "$LEAVES" <<<"$BEFORE")"
BEFORE_BAD="$(jq -n --argjson en "$EN_JSON" --argjson tr "$BEFORE" "$MISMATCH")"
EN_LEAVES="$(jq "$LEAVES" <<<"$EN_JSON")"

# Echoes "deleted orphan shape placeholder" for an after-version of the file.
gates() {
  local after="$1" after_leaves deleted orphan shape after_bad placeholder
  after_leaves="$(jq "$LEAVES" <<<"$after")"
  deleted="$(jq -n --argjson a "$BEFORE_LEAVES" --argjson b "$after_leaves" '$a - $b | length')"
  orphan="$(jq -n --argjson l "$after_leaves" --argjson p "$BEFORE_LEAVES" --argjson e "$EN_LEAVES" \
    '(($l - $e) - ($p - $e)) | length')"
  shape="$(jq -r '([paths(scalars) as $p | getpath($p) | select(type != "string")] | length)
                  + ([paths as $p | getpath($p) | select(type == "array")] | length)' <<<"$after" 2>/dev/null)" || shape="ERR"
  after_bad="$(jq -n --argjson en "$EN_JSON" --argjson tr "$after" "$MISMATCH" 2>/dev/null)" || after_bad=""
  if [[ -z "$after_bad" ]]; then
    placeholder="ERR"
  else
    placeholder="$(jq -n --argjson a "$after_bad" --argjson b "$BEFORE_BAD" '$a - $b | length')"
  fi
  echo "$deleted $orphan $shape $placeholder"
}

echo "pr-self-approval gate logic"

# A reworded value that keeps its placeholder is the case the policy exists to
# wave through.
check "clean retranslation passes every gate" "0 0 0 0" \
  "$(gates "$(jq '.["event_type_updated_successfully"] = "{{eventTypeTitle}} tipo de evento foi atualizado com sucesso"' <<<"$BEFORE")")"

check "a deleted key is caught" "1 0 0 0" \
  "$(gates "$(jq 'del(.["accept"])' <<<"$BEFORE")")"

check "a key absent from en is caught" "0 1 0 0" \
  "$(gates "$(jq '.["totally_made_up_key"] = "oi"' <<<"$BEFORE")")"

check "a dropped placeholder is caught" "0 0 0 1" \
  "$(gates "$(jq '.["event_awaiting_approval_subject"] = "Aguardando aprovacao"' <<<"$BEFORE")")"

check "a non-string value is caught" "0 0 1 1" \
  "$(gates "$(jq '.["accept"] = 42' <<<"$BEFORE")")"

# Pre-existing drift belongs to whoever introduced it, not to the next PR that
# happens to touch the file. Touching nothing must score clean.
check "pre-existing drift is not charged to this PR" "0 0 0 0" \
  "$(gates "$BEFORE")"

# An ICU plural carries the same variable as en's {{count}}, in another
# notation. Flagging it would fail correct translations.
# The ICU string is passed as an argument rather than inlined in the filter:
# bash brace-expands a bare {a,b} and would rewrite it before jq sees it.
ICU_PLURAL='{count, plural, one {1 entrada} other {# entradas}}'
check "an ICU plural is not a dropped placeholder" "0 0 0 0" \
  "$(gates "$(jq --arg v "$ICU_PLURAL" '.["entries_deleted_successfully"] = $v' <<<"$BEFORE")")"

echo
if [[ $fails -eq 0 ]]; then
  echo "all gate tests passed"
else
  echo "$fails gate test(s) failed"
  exit 1
fi
