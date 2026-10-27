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

# The whole policy. Each rule returns the reasons the evidence fails it.
POLICY='
  [ (.checks // [])[]
    | select(.exit_code != 0)
    | "check: \(.name) exited \(.exit_code)" ]'

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
      "",
      "### Checks",
      "",
      "| Check | Source | Command | Result |",
      "|---|---|---|---|",
      ((.checks // [])[] | row),
      "",
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
