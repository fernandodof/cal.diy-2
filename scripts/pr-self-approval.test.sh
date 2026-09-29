#!/usr/bin/env bash
# Tests for scripts/pr-self-approval.sh.
#
# The policy reads an evidence document and nothing else, so these tests feed it
# handwritten evidence and assert the verdict. No network, no GitHub, no git —
# which is the reason collection and policy are separate scripts.
#
# Usage: ./scripts/pr-self-approval.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$REPO_ROOT/scripts/pr-self-approval.sh"
EN_FILE="$REPO_ROOT/packages/i18n/locales/en/common.json"
BASE_FILE="$REPO_ROOT/packages/i18n/locales/pt-BR/common.json"

fails=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ok   $name"
  else
    echo "  FAIL $name: expected '$expected', got '$actual'"
    fails=$((fails + 1))
  fi
}

EN_JSON="$(cat "$EN_FILE")"
BEFORE_JSON="$(cat "$BASE_FILE")"

# Build an evidence document for a single pt-BR change. Extra top-level fields
# can be overridden by passing a jq expression as $2.
evidence() {
  local after="$1" override="${2:-.}"
  jq -n \
    --argjson en "$EN_JSON" \
    --argjson before "$BEFORE_JSON" \
    --argjson after "$after" \
    '{
      schema: "pr-evidence/1",
      collected_at: "2026-09-29T00:00:00Z",
      source_locale: "packages/i18n/locales/en/common.json",
      locale_glob: "packages/i18n/locales/*/common.json",
      merge_base: "abc123",
      pr: {
        number: 1, url: "https://example.test/pr/1", title: "translations",
        author: "fernandodof", is_draft: false,
        head_sha: "def456", base_ref: "main",
        changed_files: ["packages/i18n/locales/pt-BR/common.json"],
        changes_requested: 0,
        checks: [{name: "lint", state: "SUCCESS"}]
      },
      en_before: $en,
      locales: [{
        path: "packages/i18n/locales/pt-BR/common.json",
        locale: "pt-BR",
        after: $after, before: $before,
        after_present: true, after_parsed: true, before_parsed: true
      }]
    }' | jq "$override"
}

# Runs the policy over an evidence document and echoes "<verdict> <reason count>".
verdict() {
  local out
  out="$("$POLICY" --json --evidence <(echo "$1") 2>/dev/null)" || true
  jq -r '"\(.verdict) \(.reasons | length)"' <<<"$out"
}

echo "pr-self-approval policy"

# --- the happy path ---------------------------------------------------------
CLEAN="$(jq '.["event_type_updated_successfully"] = "{{eventTypeTitle}} tipo de evento foi atualizado com sucesso"' <<<"$BEFORE_JSON")"
check "a clean retranslation auto-approves" "auto-approve 0" \
  "$(verdict "$(evidence "$CLEAN")")"

# Touching nothing must also pass: pre-existing drift in the repo belongs to
# whoever introduced it, not to the next PR that opens the file.
check "pre-existing drift is not charged to this PR" "auto-approve 0" \
  "$(verdict "$(evidence "$BEFORE_JSON")")"

# An ICU plural carries the same variable as en's {{count}}, in another
# notation. Flagging it would fail correct translations. Passed as an argument
# because bash would brace-expand a bare {a,b} inside the filter.
ICU_PLURAL='{count, plural, one {1 entrada} other {# entradas}}'
check "an ICU plural is not a dropped placeholder" "auto-approve 0" \
  "$(verdict "$(evidence "$(jq --arg v "$ICU_PLURAL" '.["entries_deleted_successfully"] = $v' <<<"$BEFORE_JSON")")")"

# --- structural gates -------------------------------------------------------
check "a deleted key needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$(jq 'del(.["accept"])' <<<"$BEFORE_JSON")")")"

check "a key absent from en needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$(jq '.["totally_made_up_key"] = "oi"' <<<"$BEFORE_JSON")")")"

check "a dropped placeholder needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$(jq '.["event_awaiting_approval_subject"] = "Aguardando aprovacao"' <<<"$BEFORE_JSON")")")"

# A non-string value trips the shape gate and, because its placeholders can no
# longer be read, the placeholder gate too.
check "a non-string value needs a human" "needs-human 2" \
  "$(verdict "$(evidence "$(jq '.["accept"] = 42' <<<"$BEFORE_JSON")")")"

check "a file that does not parse needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$BEFORE_JSON" '.locales[0].after_parsed = false')")"

# --- scope and state gates --------------------------------------------------
check "a non-translation file needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.pr.changed_files += ["packages/lib/foo.ts"]')")"

# en matches the locale glob, so this trips the source-of-truth gate only —
# the scope gate has no quarrel with it.
check "modifying en needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.pr.changed_files += ["packages/i18n/locales/en/common.json"]')")"

check "a failing check needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.pr.checks = [{name: "lint", state: "FAILURE"}]')")"

check "no checks at all needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.pr.checks = []')")"

check "a draft needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.pr.is_draft = true')")"

check "a requested change needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.pr.changes_requested = 1')")"

check "an untrusted author needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.pr.author = "a-stranger"')")"

check "the translation bot is trusted" "auto-approve 0" \
  "$(verdict "$(evidence "$CLEAN" '.pr.author = "lingo-dot-dev[bot]"')")"

# --- evidence gates ---------------------------------------------------------
# Missing evidence must fail closed: a gate that could not run is not satisfied.
check "an unresolved merge base needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.merge_base = null')")"

check "an unreadable en needs a human" "needs-human 1" \
  "$(verdict "$(evidence "$CLEAN" '.en_before = null')")"

echo
if [[ $fails -eq 0 ]]; then
  echo "all policy tests passed"
else
  echo "$fails policy test(s) failed"
  exit 1
fi
