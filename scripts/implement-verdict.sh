#!/usr/bin/env bash
# Judge the evidence for an agent-implemented branch and render it for the PR.
#
# Pure: reads an implement-evidence/1 document (see
# docs/harness/implement-evidence-schema.md) and never touches the network,
# GitHub or git. `scripts/implement-evidence.sh` produces that document.
#
# Usage:
#   ./scripts/implement-evidence.sh … | ./scripts/implement-verdict.sh
#   ./scripts/implement-verdict.sh --evidence evidence.json
#
# Output: {verdict, labels, reasons, evidence_block} as JSON on stdout.
# Exit codes: 0 = green, 1 = red, 2 = bad usage/environment.

set -euo pipefail

EVIDENCE_FILE=""

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence) EVIDENCE_FILE="${2:-}"; [[ -n "$EVIDENCE_FILE" ]] || usage; shift 2 ;;
    -h|--help) usage ;;
    *) echo "implement-verdict: unknown argument $1" >&2; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "implement-verdict: \`jq\` is not on PATH" >&2
  exit 2
}

if [[ -n "$EVIDENCE_FILE" ]]; then
  EVIDENCE="$(cat "$EVIDENCE_FILE")" || exit 2
else
  EVIDENCE="$(cat)"
fi

jq -e 'type == "object"' >/dev/null 2>&1 <<<"$EVIDENCE" || {
  echo "implement-verdict: evidence is not a JSON object" >&2
  exit 2
}

SCHEMA="$(jq -r '.schema // ""' <<<"$EVIDENCE")"
[[ "$SCHEMA" == "implement-evidence/1" ]] || {
  echo "implement-verdict: unsupported evidence schema '${SCHEMA:-none}' (expected implement-evidence/1)" >&2
  exit 2
}

# The whole policy. Each rule returns the reasons the evidence fails it. Missing
# evidence fails closed: a fact the collector could not reach is not a pass.
POLICY='
  [ (if .merge_base == null then "evidence: the merge base with \(.base_ref) could not be resolved" else empty end),
    (if .diff == null then "evidence: the diff against the base is unavailable" else empty end),
    (if .agent == null then "evidence: the agent sessions left no summary"
     elif .phases == null and .agent.status != "completed" then "agent: the session ended \(.agent.status // "unknown")"
     else empty end),
    # Per phase, so the PR says where the sequence stopped rather than only that
    # it did. `agent` is these records summed, so it needs no rule of its own here.
    ( (.spec // "the spec") as $spec
      | (.phases // [])[]
      | if .status != "completed" then "phase \(.phase): the session ended \(.status // "without a summary")"
        elif .outcome == "blocked" then "phase \(.phase): blocked — see `\($spec)/gates/\(.phase).md`"
        elif .outcome == null then "phase \(.phase): left no gate file saying it finished"
        else empty end ),
    (if .phases != null and (.phases | length) < 3
     then "phases: stopped after \(.phases[-1].phase); \(3 - (.phases | length)) phase(s) never ran"
     else empty end),
    (if (.commits // 0) == 0 then "commits: the branch has no commits beyond the base" else empty end),
    (if ((.checks // []) | length) == 0 then "checks: none were run" else empty end),
    (if .declared_commands == null then "verification: Phase 2 declared no commands" else empty end),
    (if .criteria == null then "criteria: Phase 1 recorded no acceptance criteria" else empty end),
    # One reason per uncovered criterion: the first of these that applies.
    ( (.criteria // [])[]
      | "criterion `\(.text)`: " as $p
      | if .test_file == null then $p + "no test named"
        elif .declared != true then $p + "`\(.test_file)` is not among the declared tests"
        elif .test_found != true then $p + "`\(.test_name)` was not found in `\(.test_file)`"
        elif .test_status != "passed" then $p + "`\(.test_name)` was reported as \(.test_status)"
        else empty end ),
    ( (.rejected_commands // [])[] | "verification: rejected `\(.command)` — \(.reason)" ),
    ( (.checks // [])[]
      | if .exit_code == null then "check: \(.name) did not run"
        elif .exit_code != 0 then "check: \(.name) exited \(.exit_code)"
        else empty end ) ]'

# The block the PR body carries. The markers let a re-run replace it in place.
RENDER='
  def code: "`" + . + "`";
  def row: "| \(.name) | \(.source) | \(.command | code) | \(if .exit_code == 0 then "pass" else "fail (\(.exit_code))" end) |";
  def details: "<details><summary>\(.name) — last lines</summary>\n\n```\n\(.log_tail)\n```\n</details>";

  . as $ev
  | [ "<!-- evidence:start -->",
      "## Evidence",
      "",
      "Collected by the harness at \($ev.collected_at) — every result below is the harness re-running the check, not the agent reporting it.",
      "",
      "**Verdict: \($verdict)**",
      "",
      (if ($reasons | length) > 0 then ($reasons | map("- " + .) | join("\n")) + "\n" else empty end),
      "| | |",
      "|---|---|",
      "| Branch | \($ev.branch | code) at \($ev.head_sha[0:10] | code) |",
      "| Base | \($ev.base_ref | code) (merge base \(($ev.merge_base // "unresolved")[0:10] | code)) |",
      "| Diff | \(if $ev.diff then "\($ev.diff.files_changed) files, +\($ev.diff.insertions) −\($ev.diff.deletions)" else "unavailable" end) |",
      "| Spec | \(($ev.spec // "not found") | code) |",
      (if $ev.budget then
        "| Budget | $\($ev.budget.spent_usd * 100 | round / 100) of $\($ev.budget.cost_cap_usd); turn caps "
        + ($ev.budget.turn_caps | to_entries | map("\(.key) \(.value)") | join(", ")) + " |"
      else empty end),
      "",
      (if $ev.phases then
        "### Phases\n\n| Phase | Session | Gate | Turns | Cost |\n|---|---|---|---|---|\n"
        + ($ev.phases | map("| \(.phase) | \(.status // "no summary") | \(.outcome // "missing") | \(.turns // "–") | \(if .cost_usd then "$\(.cost_usd)" else "–" end) |") | join("\n"))
        + "\n"
      else empty end),
      (if $ev.criteria then
        "### Acceptance criteria\n\n| | Criterion | Test | Status |\n|---|---|---|---|\n"
        + ($ev.criteria | map(
            "| \(if .test_status == "passed" then "✅" else "❌" end) | \(.text) | "
            + (if .test_file then "\(.test_file | code) › \(.test_name)" else "_none named_" end)
            + " | \(.test_status // (if .test_file == null then "untagged" elif .declared | not then "not declared" else "not found" end)) |")
          | join("\n"))
        + "\n"
      else empty end),
      "### Checks",
      "",
      "| Check | Source | Command | Result |",
      "|---|---|---|---|",
      ((.checks // [])[] | row),
      "",
      (if ((.rejected_commands // []) | length) > 0 then
        "**Rejected, not run:**\n\n" + (.rejected_commands | map("- \(.command | code) — \(.reason)") | join("\n")) + "\n"
      else empty end),
      ((.checks // [])[] | select((.log_tail // "") != "") | details),
      "<!-- evidence:end -->" ]
  | join("\n")'

REASONS="$(jq -c "$POLICY" <<<"$EVIDENCE")"

if [[ "$(jq 'length' <<<"$REASONS")" -eq 0 ]]; then
  VERDICT="green"
  EXIT_CODE=0
else
  VERDICT="red"
  EXIT_CODE=1
fi

jq \
  --arg verdict "$VERDICT" \
  --argjson reasons "$REASONS" \
  "{verdict: \$verdict,
    labels: (if \$verdict == \"red\" then [\"agent:needs-help\"] else [] end),
    reasons: \$reasons,
    evidence_block: ($RENDER)}" <<<"$EVIDENCE"

exit $EXIT_CODE
