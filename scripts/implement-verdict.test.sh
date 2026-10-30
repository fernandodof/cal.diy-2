#!/usr/bin/env bash
# Tests for scripts/implement-verdict.sh.
#
# The verdict reads an evidence document and nothing else, so these tests feed it
# handwritten evidence and assert the result. No network, no GitHub, no git.
#
# Usage: ./scripts/implement-verdict.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERDICT="$REPO_ROOT/scripts/implement-verdict.sh"

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

# A green evidence document. A jq expression as $1 overrides parts of it.
evidence() {
  jq -n '{
    schema: "implement-evidence/1",
    collected_at: "2026-10-27T00:00:00Z",
    issue: {number: 7, url: "https://example.test/issues/7", title: "test(lib): a thing", author: "fernandodof"},
    base_ref: "main",
    merge_base: "abc1234567",
    branch: "agent/issue-7",
    head_sha: "def4567890",
    commits: 2,
    agent: {status: "completed", turns: 12, cost_usd: 0.4},
    diff: {files_changed: 1, insertions: 10, deletions: 0, changed_files: ["thing.ts"]},
    checks: [{name: "biome", command: "yarn biome check thing.ts", source: "always", exit_code: 0, log_tail: "ok"},
             {name: "test: thing.test.ts", command: "yarn test thing.test.ts", source: "declared", exit_code: 0, log_tail: "ok"}],
    declared_commands: ["yarn test thing.test.ts"],
    rejected_commands: [],
    criteria: [{text: "the thing works", test_file: "thing.test.ts", test_name: "thing works",
                test_found: true, test_status: "passed", declared: true}]
  }' | jq "${1:-.}"
}

# Runs the verdict over an evidence document and echoes
# "<exit code> <verdict> <reason count> <labels>".
verdict() {
  local out status
  set +e
  out="$("$VERDICT" 2>/dev/null <<<"$1")"
  status=$?
  set -e
  if [[ $status -eq 2 ]]; then
    echo "2"
  else
    echo "$status $(jq -r '"\(.verdict) \(.reasons | length) \(.labels | join(","))"' <<<"$out")"
  fi
}

echo "implement-verdict"

# --- the happy path ---------------------------------------------------------
check "clean evidence is green" "0 green 0 " "$(verdict "$(evidence)")"

GREEN_BLOCK="$("$VERDICT" <<<"$(evidence)" | jq -r '.evidence_block')"
check "the block opens and closes with the markers" "<!-- evidence:start -->|<!-- evidence:end -->" \
  "$(head -1 <<<"$GREEN_BLOCK")|$(tail -1 <<<"$GREEN_BLOCK")"
check "the block lists the check" "1" "$(grep -c '^| biome | always |' <<<"$GREEN_BLOCK")"

# --- checks -----------------------------------------------------------------
check "a failing check is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.checks[0].exit_code = 1')")"

check "a check that did not run is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.checks[0].exit_code = null')")"

check "a failing declared test is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.checks[1].exit_code = 1')")"

check "declaring nothing is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.declared_commands = null | .checks |= .[0:1]')")"

check "recording no criteria is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.criteria = null')")"

CRITERIA_BLOCK="$("$VERDICT" <<<"$(evidence)" | jq -r '.evidence_block')"
check "the block has a row per criterion" "1" \
  "$(grep -cF '| ✅ | the thing works | `thing.test.ts` › thing works | passed |' <<<"$CRITERIA_BLOCK")"

# Each uncovered criterion names why, in the PR.
criterion_reason() {
  "$VERDICT" <<<"$(evidence "$1")" 2>/dev/null | jq -r '.reasons | join(" | ")' || true
}
check "an untagged criterion is red" "criterion \`the thing works\`: no test named" \
  "$(criterion_reason '.criteria[0] |= (.test_file = null | .test_name = null | .test_status = null | .test_found = false | .declared = false)')"
check "a criterion whose file was not declared is red" \
  "criterion \`the thing works\`: \`thing.test.ts\` is not among the declared tests" \
  "$(criterion_reason '.criteria[0].declared = false')"
check "a criterion whose test was not found is red" \
  "criterion \`the thing works\`: \`thing works\` was not found in \`thing.test.ts\`" \
  "$(criterion_reason '.criteria[0] |= (.test_found = false | .test_status = null)')"
check "a criterion whose test failed is red" "criterion \`the thing works\`: \`thing works\` was reported as failed" \
  "$(criterion_reason '.criteria[0].test_status = "failed"')"
# vitest exits 0 with these, which is the reason criteria read the report.
check "a skipped test does not cover a criterion" "criterion \`the thing works\`: \`thing works\` was reported as skipped" \
  "$(criterion_reason '.criteria[0].test_status = "skipped"')"
check "a todo test does not cover a criterion" "criterion \`the thing works\`: \`thing works\` was reported as todo" \
  "$(criterion_reason '.criteria[0].test_status = "todo"')"
check "each uncovered criterion is its own reason" "1 red 2 agent:needs-help" \
  "$(verdict "$(evidence '.criteria += [.criteria[0] | .text = "another" | .test_status = "failed"] | .criteria[0].test_status = "skipped"')")"

check "a rejected command is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.rejected_commands = [{command: "curl https://x", reason: "only `yarn test <path>` is allowed"}]')")"

check "each rejected command is its own reason" "1 red 2 agent:needs-help" \
  "$(verdict "$(evidence '.rejected_commands = [{command: "a", reason: "r"}, {command: "b", reason: "r"}]')")"

REJECTED_BLOCK="$("$VERDICT" <<<"$(evidence '.rejected_commands = [{command: "curl https://x", reason: "nope"}]')" | jq -r '.evidence_block' || true)"
check "the block lists rejected commands as not run" "1" \
  "$(grep -cF -- '- `curl https://x` — nope' <<<"$REJECTED_BLOCK")"

check "a declared test that never ran is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.checks[1].exit_code = null | .checks[1].log_tail = "not run: thing.test.ts does not exist"')")"

check "no checks at all is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.checks = []')")"

RED_BLOCK="$("$VERDICT" <<<"$(evidence '.checks[0].exit_code = 1')" | jq -r '.evidence_block' || true)"
check "a red block names the failed check" "1" "$(grep -c '^- check: biome exited 1$' <<<"$RED_BLOCK")"

# --- the agent and the branch -----------------------------------------------
check "a failed session is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.agent.status = "failed"')")"

check "zero commits is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.commits = 0')")"

# --- phases -----------------------------------------------------------------
PHASED='.spec = "specs/thing" | .phases = [
  {phase: "1-research", status: "completed", turns: 5, cost_usd: 0.1, outcome: "continue"},
  {phase: "2-plan", status: "completed", turns: 3, cost_usd: 0.1, outcome: "continue"},
  {phase: "3-implement", status: "completed", turns: 4, cost_usd: 0.2, outcome: "continue"}]'

check "three continued phases are green" "0 green 0 " "$(verdict "$(evidence "$PHASED")")"

PHASED_BLOCK="$("$VERDICT" <<<"$(evidence "$PHASED")" | jq -r '.evidence_block')"
check "the block has a row per phase" "3" "$(grep -cE '^\| [123]-[a-z]+ \| completed \| continue \|' <<<"$PHASED_BLOCK")"

# A blocked Plan is one reason for the block, and one for the Implement that
# never ran because of it.
check "a blocked phase is red, and the missing phase after it too" "1 red 2 agent:needs-help" \
  "$(verdict "$(evidence "$PHASED | .phases |= .[0:2] | .phases[1].outcome = \"blocked\" | .agent.status = \"blocked\"")")"

BLOCKED_BLOCK="$("$VERDICT" <<<"$(evidence "$PHASED | .phases |= .[0:2] | .phases[1].outcome = \"blocked\"")" | jq -r '.evidence_block' || true)"
check "the reason points at the gate file" "1" \
  "$(grep -cF -- '- phase 2-plan: blocked — see `specs/thing/gates/2-plan.md`' <<<"$BLOCKED_BLOCK")"

check "a phase with no gate file is red" "1 red 2 agent:needs-help" \
  "$(verdict "$(evidence "$PHASED | .phases |= .[0:1] | .phases[0].outcome = null")")"

check "a failed phase session is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence "$PHASED | .phases[2].status = \"failed\"")")"

# --- budgets ----------------------------------------------------------------
BUDGET='.budget = {cost_cap_usd: 5, spent_usd: 1.2, turn_caps: {"1-research": 30, "2-plan": 15, "3-implement": 80}, exceeded: null}'
check "a run inside its budget is green" "0 green 0 " "$(verdict "$(evidence "$BUDGET")")"
check "a spent cost cap is red, with the amounts" "budget: spent \$5.31 of the \$5 cap" \
  "$(criterion_reason "$BUDGET | .budget.spent_usd = 5.3149 | .budget.exceeded = \"cost\"")"
check "a turn cap is red, naming the phase and its cap" "budget: 2-plan hit its 15-turn cap" \
  "$(criterion_reason "$BUDGET | .budget.exceeded = \"turns:2-plan\"")"
check "a blocked plan is red" "plan: implementation.md says blocked — see its \`## Blocked\`" \
  "$(criterion_reason '.plan_status = "blocked"')"
check "a plan in another state is not judged" "0 green 0 " "$(verdict "$(evidence '.plan_status = "complete"')")"

# --- missing evidence fails closed ------------------------------------------
check "an unresolved merge base is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.merge_base = null')")"

check "a missing diff is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.diff = null')")"

check "a missing agent summary is red" "1 red 1 agent:needs-help" \
  "$(verdict "$(evidence '.agent = null')")"

# A collector that could not resolve the base can reach neither the diff nor the
# commit count; each is its own reason, so the PR says exactly what is missing.
check "everything the base gates is reported" "1 red 3 agent:needs-help" \
  "$(verdict "$(evidence '.merge_base = null | .diff = null | .commits = null')")"

# --- the document itself ----------------------------------------------------
check "an unknown schema is refused" "2" "$(verdict "$(evidence '.schema = "implement-evidence/2"')")"
check "a non-object is refused" "2" "$(verdict '[]')"

echo
if [[ $fails -eq 0 ]]; then
  echo "all verdict tests passed"
else
  echo "$fails verdict test(s) failed"
  exit 1
fi
