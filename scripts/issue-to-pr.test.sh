#!/usr/bin/env bash
# Tests for scripts/issue-to-pr.sh.
#
# `claude`, `gh` and `yarn` are replaced by fakes on PATH that log how they were
# called; git is real, against a throwaway repo with a bare remote. That runs the
# whole orchestrator — worktree, agent session, collector, verdict, push, PR —
# with no network and no model.
#
# Usage: ./scripts/issue-to-pr.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# Build a sandbox: a bare origin, a clone holding the harness scripts, and a bin
# directory of fakes. Echoes the sandbox path.
sandbox() {
  local sb
  sb="$(mktemp -d)"
  git init --quiet --bare --initial-branch=main "$sb/origin.git"
  git init --quiet --initial-branch=main "$sb/repo"
  mkdir -p "$sb/repo/scripts" "$sb/bin" "$sb/log"
  cp "$REPO_ROOT"/scripts/{issue-to-pr,headless-task,implement-evidence,implement-verdict}.sh "$sb/repo/scripts/"
  (
    cd "$sb/repo"
    git config user.email test@example.test
    git config user.name test
    git add -A && git commit --quiet -m "init"
    git remote add origin "$sb/origin.git"
    git push --quiet -u origin main
    # A second base, with a commit main does not have.
    git checkout --quiet -b release
    echo "release" > release.txt && git add release.txt && git commit --quiet -m "release only"
    git push --quiet -u origin release
    git checkout --quiet main
  )

  # gh: canned issue, recorded PR calls.
  cat > "$sb/bin/gh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG/gh.log"
case "$1 $2" in
  "issue view")
    jq -n --arg author "${FAKE_ISSUE_AUTHOR:-fernandodof}" --arg labels "${FAKE_ISSUE_LABELS:-}" \
      --arg body "${FAKE_ISSUE_BODY:-Add a test.}" \
      '{number: 7, title: "test(lib): cover a thing", body: $body,
        url: "https://example.test/issues/7", author: {login: $author},
        labels: ($labels | split(" ") | map(select(. != "") | {name: .}))}' ;;
  "repo view") [[ "$*" == *nameWithOwner* ]] && echo "fernandodof/cal.diy-2" || echo "fernandodof" ;;
  "issue comment"|"issue edit") ;;
  "pr create") echo "https://example.test/pull/99" ;;
  "label list") { printf '%s\n' ${FAKE_EXISTING_LABELS:-}; cat "$FAKE_LOG/labels" 2>/dev/null || true; } ;;
  "label create") echo "$3" >> "$FAKE_LOG/labels" ;;
  "pr edit") ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE

  # claude: records its flags and stdin, then acts out the phase it was asked to
  # run, in its cwd. FAKE_CLAUDE picks what Phase 3 commits (commit, docs, fail,
  # or nothing at all in any phase); FAKE_OUTCOME_<n>, FAKE_NO_GATE=<n> and
  # FAKE_FAIL_PHASE=<n> bend a single phase.
  cat > "$sb/bin/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_LOG/claude.args"
cat > "$FAKE_LOG/claude.stdin"
pwd > "$FAKE_LOG/claude.cwd"
# The prompt may not end in a newline; give each call its own line regardless.
printf '%s\n' "$(head -1 "$FAKE_LOG/claude.stdin")" >> "$FAKE_LOG/claude.calls"
phase="$(head -1 "$FAKE_LOG/claude.stdin" | sed -n 's/.*--phase \([0-9]\).*/\1/p')"
mode="${FAKE_CLAUDE:-commit}"
outcome_var="FAKE_OUTCOME_${phase:-0}"
gate() {
  [[ "${FAKE_NO_GATE:-}" == "$phase" ]] && return
  printf 'Outcome: %s\n\nphase %s summary\n' "${!outcome_var:-continue}" "$phase" > "specs/thing/gates/$1.md"
}
if [[ -n "$phase" && "$mode" != nothing ]]; then
  mkdir -p specs/thing/gates
  case "$phase" in
    1)
      # FAKE_CRITERIA replaces the acceptance criteria; set it empty to record none.
      printf '# design\n\n## Acceptance Criteria\n\n%s\n\n## Technical Design\n' \
        "${FAKE_CRITERIA-- [ ] the thing works — \`thing.test.ts\` › thing works}" > specs/thing/design.md
      gate 1-research ;;
    2)
      # FAKE_VERIFY replaces the declared commands; set it empty to declare none.
      printf '# plan\n\n## Verification\n\n```sh\n%s\n```\n' \
        "${FAKE_VERIFY-yarn test thing.test.ts}" > specs/thing/implementation.md
      gate 2-plan ;;
    3)
      if [[ "$mode" == docs ]]; then
        echo "# notes" > notes.md
      else
        echo "export const x = 1;" > thing.ts
        echo "it('x', () => {});" > thing.test.ts
      fi
      gate 3-implement
      mkdir -p .claude/headless-runs
      printf '## What changed\n\nThe agent draft.\n' > .claude/headless-runs/pr-body.md ;;
  esac
  # Everything but the PR body draft, which headless.md says is never committed.
  git add -A -- . ':!.claude'
  git -c user.email=a@b -c user.name=agent commit --quiet -m "phase $phase"
fi
if [[ -n "$phase" && ( "${FAKE_FAIL_PHASE:-}" == "$phase" || ( "$mode" == fail && "$phase" == 3 ) ) ]]; then
  echo '{"is_error": true, "subtype": "error_max_turns", "num_turns": 40, "total_cost_usd": 1}'
else
  echo '{"is_error": false, "subtype": "success", "result": "Did the thing.", "num_turns": 3, "total_cost_usd": 0.1}'
fi
FAKE

  # score.sh: FAKE_SCORE grades the issue (default 3); "none" mimics its parse failure.
  cat > "$sb/bin/score" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG/score.log"
if [[ "${FAKE_SCORE:-3}" == none ]]; then
  echo '{"id":"x","score":null,"reasoning":"PARSE_FAILURE","raw":""}'
else
  jq -nc --argjson score "${FAKE_SCORE:-3}" '{id: "x", score: $score, reasoning: "The issue never says which unit wins."}'
fi
FAKE

  # yarn: records each call; FAKE_YARN_FAIL names a subcommand that exits 1.
  cat > "$sb/bin/yarn" <<'FAKE'
#!/usr/bin/env bash
echo "$* cwd=$PWD cache=${YARN_CACHE_FOLDER:-}" >> "$FAKE_LOG/yarn.log"
[[ -n "${FAKE_YARN_FAIL:-}" && "$*" == *"$FAKE_YARN_FAIL"* ]] && { echo "boom"; exit 1; }
[[ -n "${FAKE_YARN_NO_TESTS:-}" && "$1" == test ]] && { echo "No test files found, exiting with code 0"; exit 0; }
# yarn test: write the JSON report the collector asks for, one test per file,
# named and graded by FAKE_TEST_NAME / FAKE_TEST_STATUS.
if [[ "$1" == test ]]; then
  report="" files=()
  for arg in "${@:2}"; do
    case "$arg" in
      --outputFile.json=*) report="${arg#--outputFile.json=}" ;;
      --*) ;;
      *) files+=("$arg") ;;
    esac
  done
  [[ -n "$report" ]] && printf '%s\n' "${files[@]}" \
    | jq -R --arg pwd "$PWD" --arg name "${FAKE_TEST_NAME:-thing works}" --arg status "${FAKE_TEST_STATUS:-passed}" \
        '{name: "\($pwd)/\(.)", assertionResults: [{fullName: $name, status: $status}]}' \
    | jq -s '{testResults: .}' > "$report"
fi
exit 0
FAKE
  chmod +x "$sb/bin/"*
  echo "$sb"
}

# Run the harness in a sandbox; echoes its exit code. Extra env as "K=V" args.
run() {
  local sb="$1"; shift
  set +e
  env "$@" \
    PATH="$sb/bin:$PATH" \
    FAKE_LOG="$sb/log" \
    HEADLESS_TASK_OUT_DIR="$sb/runs" \
    ISSUE_TO_PR_WORKTREE_DIR="$sb/worktrees" \
    ISSUE_TO_PR_SCORER="$sb/bin/score" \
    "$sb/repo/scripts/issue-to-pr.sh" ${RUN_ARGS:-} 7 > "$sb/log/stdout" 2> "$sb/log/stderr"
  echo $?
  set -e
}

echo "issue-to-pr orchestrator"

# --- green path -------------------------------------------------------------
SB="$(sandbox)"
check "a clean run exits 0" "0" "$(run "$SB")"
check "it prints the PR URL" "https://example.test/pull/99" "$(cat "$SB/log/stdout")"
check "the agent ran inside the worktree" "$SB/worktrees/issue-7" "$(cat "$SB/log/claude.cwd")"
check "three phase sessions ran in order" "1 2 3" \
  "$(sed -n 's/.*--headless --phase \([0-9]\).*/\1/p' "$SB/log/claude.calls" | xargs)"
check "phase 1 is given the issue, not a spec" "no" \
  "$(head -1 "$SB/log/claude.calls" | grep -q -- --spec && echo yes || echo no)"
check "phases 2 and 3 are given the spec Phase 1 added" "2" \
  "$(grep -c -- '--base main https://example.test/issues/7 --spec specs/thing$' "$SB/log/claude.calls")"
# The prompt is a request; the permission flags are the enforcement.
flag_value() { grep -A1 -xF -- "$1" "$SB/log/claude.args" | tail -1; }
check "pushing is denied to the agent" "yes" \
  "$(flag_value --disallowedTools | tr ',' '\n' | grep -qxF 'Bash(git push:*)' && echo yes || echo no)"
check "every gh pr command is denied to the agent" "yes" \
  "$(flag_value --disallowedTools | tr ',' '\n' | grep -qxF 'Bash(gh pr:*)' && echo yes || echo no)"
check "the agent may run the tests #11 was denied" "yes" \
  "$(flag_value --allowedTools | tr ',' '\n' | grep -qxF 'Bash(yarn test:*)' && echo yes || echo no)"
check "nothing that pushes or opens a PR is allowed" "0" \
  "$(flag_value --allowedTools | tr ',' '\n' | grep -cE '^Bash\((git push|gh pr|git:|gh:)' || true)"
check "the branch reached origin" "yes" \
  "$(git -C "$SB/origin.git" rev-parse --verify --quiet refs/heads/agent/issue-7 >/dev/null && echo yes || echo no)"
check "the user's checkout stayed on main" "main" "$(git -C "$SB/repo" rev-parse --abbrev-ref HEAD)"
check "one draft PR against main" "1" \
  "$(grep -c '^pr create --draft --base main --head agent/issue-7 ' "$SB/log/gh.log")"
BODY="$SB/runs/issue-7/pr-body.md"
check "the body carries the evidence markers" "2" \
  "$(grep -cE '^<!-- evidence:(start|end) -->$' "$BODY")"
check "the body reports a green verdict" "1" "$(grep -c '^\*\*Verdict: green\*\*$' "$BODY")"
check "biome was re-run by the harness on the changed file" "1" \
  "$(grep -c '^biome check .*thing.ts cwd='"$SB/worktrees/issue-7" "$SB/log/yarn.log")"
check "the evidence records one commit per phase" "3" "$(jq '.commits' "$SB/runs/issue-7/evidence.json")"
check "the evidence records the spec and the three phases" "specs/thing 3" \
  "$(jq -r '"\(.spec) \(.phases | length)"' "$SB/runs/issue-7/evidence.json")"
check "the body opens with the agent's draft" "1" "$(grep -c '^The agent draft\.$' "$BODY")"
check "the body links every gate file" "3" "$(grep -c '^- `specs/thing/gates/.*` — Outcome: continue$' "$BODY")"
check "the draft comes before the evidence" "yes" \
  "$([[ $(grep -n 'The agent draft' "$BODY" | cut -d: -f1) -lt $(grep -n 'evidence:start' "$BODY" | cut -d: -f1) ]] && echo yes || echo no)"
check "the worktree got its own install from this checkout's cache" "1" \
  "$(grep -c "^install --immutable cwd=$SB/worktrees/issue-7 cache=$SB/repo/.yarn/cache$" "$SB/log/yarn.log")"
check "the install ran before the agent" "install" "$(head -1 "$SB/log/yarn.log" | cut -d' ' -f1)"
check "type-check was re-run by the harness in the worktree" "1" \
  "$(grep -c "^turbo run type-check --filter=@calcom/web cwd=$SB/worktrees/issue-7 " "$SB/log/yarn.log")"
check "the evidence carries the always-on and the declared checks" "type-check:always,biome:always,test: thing.test.ts:declared" \
  "$(jq -r '[.checks[] | "\(.name):\(.source)"] | join(",")' "$SB/runs/issue-7/evidence.json")"
check "the harness ran the declared test in the worktree" "1" \
  "$(grep -c "^test thing.test.ts --reporter.* cwd=$SB/worktrees/issue-7 " "$SB/log/yarn.log")"
check "the evidence records what Phase 2 declared" '["yarn test thing.test.ts"]' \
  "$(jq -c '.declared_commands' "$SB/runs/issue-7/evidence.json")"
check "the declared run was asked for a JSON report" "1" \
  "$(grep -c '^test thing.test.ts --reporter=default --reporter=json --outputFile.json=' "$SB/log/yarn.log")"
check "the criterion was found in the harness's own run, and passed" "true passed true" \
  "$(jq -r '.criteria[0] | "\(.test_found) \(.test_status) \(.declared)"' "$SB/runs/issue-7/evidence.json")"
check "the body has the criteria table" "1" \
  "$(grep -cF '| ✅ | the thing works | `thing.test.ts` › thing works | passed |' "$BODY")"
check "a second run refuses the existing branch" "2" "$(run "$SB")"
check "all three labels are created on first use" "3" "$(grep -c '^label create agent:' "$SB/log/gh.log")"
check "a green PR is not labelled" "0" "$(grep -c '^pr create .*--label' "$SB/log/gh.log")"
rm -rf "$SB"

# --- base branch ------------------------------------------------------------
# Every use of the base: the worktree cut, each phase prompt, the evidence diff,
# the PR. Echoes "<has release.txt> <prompts naming it> <evidence base> <PR base>".
base_uses() {
  local base="$1"
  echo "$([[ -f "$SB/worktrees/issue-7/release.txt" ]] && echo yes || echo no)" \
    "$(grep -c -- "--base $base " "$SB/log/claude.calls")" \
    "$(jq -r '.base_ref' "$SB/runs/issue-7/evidence.json")" \
    "$(sed -n 's/^pr create --draft --base \([^ ]*\) .*/\1/p' "$SB/log/gh.log")"
}

SB="$(sandbox)"
run "$SB" >/dev/null
check "with no override everything uses main" "no 3 main main" "$(base_uses main)"
rm -rf "$SB"

SB="$(sandbox)"
check "a base: label runs green" "0" "$(run "$SB" FAKE_ISSUE_LABELS="base:release")"
check "  and moves every use to that branch" "yes 3 release release" "$(base_uses release)"
rm -rf "$SB"

SB="$(sandbox)"
check "a Base: line in the body runs green" "0" "$(run "$SB" FAKE_ISSUE_BODY=$'Add a test.\n\nBase: `release`\n')"
check "  and moves every use to that branch" "yes 3 release release" "$(base_uses release)"
rm -rf "$SB"

SB="$(sandbox)"
check "a label and a body line that agree run green" "0" \
  "$(run "$SB" FAKE_ISSUE_LABELS="base:release" FAKE_ISSUE_BODY=$'Base: release')"
rm -rf "$SB"

# --- trust gate -------------------------------------------------------------
SB="$(sandbox)"
check "an issue by someone else is refused" "3" "$(run "$SB" FAKE_ISSUE_AUTHOR=a-stranger)"
check "the refusal names the author" "1" "$(grep -c "written by 'a-stranger', not the repo owner 'fernandodof'" "$SB/log/stderr")"
check "only reads reached GitHub" "issue view,repo view" \
  "$(cut -d' ' -f1-2 "$SB/log/gh.log" | paste -sd, -)"
check "no branch was created" "no" \
  "$(git -C "$SB/repo" rev-parse --verify --quiet refs/heads/agent/issue-7 >/dev/null && echo yes || echo no)"
check "no worktree was created" "no" "$([[ -d "$SB/worktrees/issue-7" ]] && echo yes || echo no)"
check "no agent ran" "no" "$([[ -f "$SB/log/claude.calls" ]] && echo yes || echo no)"
rm -rf "$SB"

SB="$(sandbox)"
check "--trust runs someone else's issue" "0" "$(RUN_ARGS=--trust run "$SB" FAKE_ISSUE_AUTHOR=a-stranger)"
check "and opens its draft PR" "1" "$(grep -c '^pr create --draft ' "$SB/log/gh.log")"
rm -rf "$SB"

# --- ambiguity gate ---------------------------------------------------------
SB="$(sandbox)"
run "$SB" >/dev/null
check "a clear issue is scored, against this repo" "--issue fernandodof/cal.diy-2#7" "$(cat "$SB/log/score.log")"
check "a clear issue posts no comment" "0" "$(grep -c '^issue comment' "$SB/log/gh.log" || true)"
rm -rf "$SB"

for score in 1 0; do
  SB="$(sandbox)"
  check "a score of $score is refused" "3" "$(run "$SB" FAKE_SCORE=$score)"
  check "  it comments once" "1" "$(grep -c '^issue comment 7 ' "$SB/log/gh.log")"
  check "  the comment carries the judge's reasoning" "1" \
    "$(grep -c '> The issue never says which unit wins.' "$SB/log/gh.log")"
  check "  the comment carries the score" "1" "$(grep -c "scored \*\*$score / 3\*\*" "$SB/log/gh.log")"
  check "  the issue is labelled needs-clarification" "1" \
    "$(grep -c '^issue edit 7 --add-label agent:needs-clarification$' "$SB/log/gh.log")"
  check "  the label exists before it is used" "yes" \
    "$([[ $(grep -n '^label create agent:needs-clarification' "$SB/log/gh.log" | cut -d: -f1) -lt $(grep -n '^issue edit' "$SB/log/gh.log" | cut -d: -f1) ]] && echo yes || echo no)"
  check "  no worktree, branch or agent" "no no no" \
    "$([[ -d "$SB/worktrees/issue-7" ]] && echo yes || echo no) $(git -C "$SB/repo" rev-parse --verify --quiet refs/heads/agent/issue-7 >/dev/null && echo yes || echo no) $([[ -f "$SB/log/claude.calls" ]] && echo yes || echo no)"
  rm -rf "$SB"
done

SB="$(sandbox)"
check "a score of 2 proceeds" "0" "$(run "$SB" FAKE_SCORE=2)"
rm -rf "$SB"

SB="$(sandbox)"
check "a judge that gave no score is an environment error" "2" "$(run "$SB" FAKE_SCORE=none)"
check "  it posts no comment and adds no label" "0" "$(grep -cE '^issue (comment|edit)' "$SB/log/gh.log" || true)"
check "  and starts nothing" "no" "$([[ -d "$SB/worktrees/issue-7" ]] && echo yes || echo no)"
rm -rf "$SB"

SB="$(sandbox)"
check "a clarified issue proceeds" "0" "$(run "$SB" FAKE_ISSUE_LABELS="agent:needs-clarification bug")"
check "  and sheds its needs-clarification label" "1" \
  "$(grep -c '^issue edit 7 --remove-label agent:needs-clarification$' "$SB/log/gh.log")"
rm -rf "$SB"

# --- red path ---------------------------------------------------------------
SB="$(sandbox)"
check "a failing check exits 1" "1" "$(run "$SB" FAKE_YARN_FAIL="biome check")"
check "a red run still opens a draft PR" "1" "$(grep -c '^pr create --draft ' "$SB/log/gh.log")"
check "the red PR is labelled agent:needs-help" "1" \
  "$(grep -c '^pr create .*--label agent:needs-help' "$SB/log/gh.log")"
check "the body names the failed check" "1" \
  "$(grep -c '^- check: biome exited 1$' "$SB/runs/issue-7/pr-body.md")"
check "the failing log reaches the body" "1" "$(grep -cx 'boom' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

SB="$(sandbox)"
check "a failing type-check exits 1" "1" "$(run "$SB" FAKE_YARN_FAIL="type-check")"
check "the body names the failed type-check" "1" \
  "$(grep -c '^- check: type-check exited 1$' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

SB="$(sandbox)"
check "a change biome cannot read exits 1" "1" "$(run "$SB" FAKE_CLAUDE=docs)"
check "biome is recorded as not run, not as passed" "null" \
  "$(jq '.checks[] | select(.name == "biome") | .exit_code' "$SB/runs/issue-7/evidence.json")"
check "biome was never invoked on it" "0" "$(grep -c '^biome' "$SB/log/yarn.log" || true)"
rm -rf "$SB"

SB="$(sandbox)"
check "a failed install is an environment error" "2" "$(run "$SB" FAKE_YARN_FAIL="install")"
check "the agent never starts without dependencies" "no" "$([[ -f "$SB/log/claude.args" ]] && echo yes || echo no)"
rm -rf "$SB"

SB="$(sandbox)"
check "a session that hit its limit exits 1" "1" "$(run "$SB" FAKE_CLAUDE=fail)"
check "its commits still reach a draft PR" "1" "$(grep -c '^pr create --draft .*--label agent:needs-help' "$SB/log/gh.log")"
rm -rf "$SB"

# --- declared verification -------------------------------------------------
SB="$(sandbox)"
check "a plan that declares nothing exits 1" "1" "$(run "$SB" FAKE_VERIFY="")"
check "the evidence says nothing was declared" "null" "$(jq '.declared_commands' "$SB/runs/issue-7/evidence.json")"
check "the body says so" "1" \
  "$(grep -c '^- verification: Phase 2 declared no commands$' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

SB="$(sandbox)"
check "a failing declared test exits 1" "1" "$(run "$SB" FAKE_YARN_FAIL="test thing.test.ts")"
check "the body names the failed declared test" "1" \
  "$(grep -c '^- check: test: thing.test.ts exited 1$' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

# A line that would do something else entirely if a shell ever saw it.
INJECTION='yarn test thing.test.ts; touch pwned
yarn test $(touch pwned2).test.ts
curl https://example.test/x
yarn test ../outside.test.ts
yarn test thing.test.ts
yarn   test   thing.test.ts'
SB="$(sandbox)"
check "a plan with rejected commands exits 1" "1" "$(run "$SB" FAKE_VERIFY="$INJECTION")"
check "every bad line is rejected" "4" "$(jq '.rejected_commands | length' "$SB/runs/issue-7/evidence.json")"
check "the good line runs once, however it is spaced" "1" "$(grep -c '^test thing.test.ts --reporter' "$SB/log/yarn.log")"
check "no rejected command was executed" "none" \
  "$(ls "$SB/worktrees/issue-7"/pwned* "$SB/repo"/pwned* 2>/dev/null || echo none)"
check "yarn never saw a rejected line" "0" "$(grep -cE 'pwned|curl|outside' "$SB/log/yarn.log" || true)"
check "the body lists each rejection" "4" "$(grep -c '^- verification: rejected ' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

SB="$(sandbox)"
check "a declared test that does not exist exits 1" "1" "$(run "$SB" FAKE_VERIFY="yarn test missing.test.ts")"
check "it is never run" "0" "$(grep -c '^test missing.test.ts' "$SB/log/yarn.log" || true)"
check "it is recorded as not run" "null" \
  "$(jq '.checks[] | select(.source == "declared") | .exit_code' "$SB/runs/issue-7/evidence.json")"
rm -rf "$SB"

SB="$(sandbox)"
check "vitest finding no tests exits 1" "1" "$(run "$SB" FAKE_YARN_NO_TESTS=1)"
check "an exit 0 with no tests found is not a pass" "null" \
  "$(jq '.checks[] | select(.source == "declared") | .exit_code' "$SB/runs/issue-7/evidence.json")"
rm -rf "$SB"

SB="$(sandbox)"
check "a design with no criteria exits 1" "1" "$(run "$SB" FAKE_CRITERIA="")"
check "the evidence says none were recorded" "null" "$(jq '.criteria' "$SB/runs/issue-7/evidence.json")"
check "the body says so" "1" \
  "$(grep -c '^- criteria: Phase 1 recorded no acceptance criteria$' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

SB="$(sandbox)"
check "a skipped tagged test exits 1, though its run exits 0" "1" "$(run "$SB" FAKE_TEST_STATUS=skipped)"
check "the declared run itself passed" "0" \
  "$(jq '.checks[] | select(.source == "declared") | .exit_code' "$SB/runs/issue-7/evidence.json")"
check "the body says the criterion's test was skipped" "1" \
  "$(grep -cF -- '- criterion `the thing works`: `thing works` was reported as skipped' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

SB="$(sandbox)"
check "a renamed test exits 1" "1" "$(run "$SB" FAKE_TEST_NAME="thing still works")"
check "the criterion's test is not found" "false" "$(jq '.criteria[0].test_found' "$SB/runs/issue-7/evidence.json")"
rm -rf "$SB"

SB="$(sandbox)"
check "a criterion naming an undeclared file exits 1" "1" \
  "$(run "$SB" FAKE_CRITERIA='- [ ] other — `other.test.ts` › other works')"
check "the undeclared file was never run" "0" "$(grep -c '^test other.test.ts' "$SB/log/yarn.log" || true)"
check "the criterion is marked not declared" "false" "$(jq '.criteria[0].declared' "$SB/runs/issue-7/evidence.json")"
rm -rf "$SB"

# --- a stopped sequence -----------------------------------------------------
SB="$(sandbox)"
check "a failed phase 1 exits 1" "1" "$(run "$SB" FAKE_FAIL_PHASE=1)"
check "no phase starts after a failed one" "1" "$(wc -l < "$SB/log/claude.calls" | xargs)"
check "the partial work still reaches a red draft PR" "1" \
  "$(grep -c '^pr create --draft .*--label agent:needs-help' "$SB/log/gh.log")"
check "the body says which phase failed" "1" \
  "$(grep -c '^- phase 1-research: the session ended failed$' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

SB="$(sandbox)"
check "a blocked phase 2 exits 1" "1" "$(run "$SB" FAKE_OUTCOME_2=blocked)"
check "phase 3 never starts after a blocked plan" "1 2" \
  "$(sed -n 's/.*--headless --phase \([0-9]\).*/\1/p' "$SB/log/claude.calls" | xargs)"
check "the body points at the blocked gate" "1" \
  "$(grep -cF -- '- phase 2-plan: blocked — see `specs/thing/gates/2-plan.md`' "$SB/runs/issue-7/pr-body.md")"
check "the gate list shows the blocked outcome" "1" \
  "$(grep -c '^- `specs/thing/gates/2-plan.md` — Outcome: blocked$' "$SB/runs/issue-7/pr-body.md")"
check "the body says the agent left no draft" "1" \
  "$(grep -c '^_The agent left no PR body draft' "$SB/runs/issue-7/pr-body.md")"
rm -rf "$SB"

SB="$(sandbox)"
check "a phase 1 with no gate file exits 1" "1" "$(run "$SB" FAKE_NO_GATE=1)"
check "nothing runs without a spec to hand on" "1" "$(wc -l < "$SB/log/claude.calls" | xargs)"
check "the evidence records no spec" "null" "$(jq '.spec' "$SB/runs/issue-7/evidence.json")"
rm -rf "$SB"

SB="$(sandbox)"
check "a run with no commits exits 1" "1" "$(run "$SB" FAKE_CLAUDE=nothing)"
check "it opens no PR" "0" "$(grep -c '^pr create' "$SB/log/gh.log" || true)"
check "it pushes nothing" "no" \
  "$(git -C "$SB/origin.git" rev-parse --verify --quiet refs/heads/agent/issue-7 >/dev/null && echo yes || echo no)"
rm -rf "$SB"

SB="$(sandbox)"
run "$SB" FAKE_EXISTING_LABELS="agent:implement agent:needs-help" >/dev/null
check "existing labels are left alone" "label create agent:needs-clarification" \
  "$(grep '^label create' "$SB/log/gh.log" | cut -d' ' -f1-3)"
rm -rf "$SB"

# --- headless-task.sh on its own --------------------------------------------
# Callers that pass none of the new flags must get the session they always did.
SB="$(sandbox)"
(cd "$SB/repo" && PATH="$SB/bin:$PATH" FAKE_LOG="$SB/log" FAKE_CLAUDE=nothing \
  HEADLESS_TASK_OUT_DIR="$SB/runs" ./scripts/headless-task.sh "a task" >/dev/null 2>&1)
check "without --workdir the session runs in the repo" "$(cd "$SB/repo" && pwd)" "$(cat "$SB/log/claude.cwd")"
check "without --workdir the repo is the added dir" "$(cd "$SB/repo" && pwd)" \
  "$(grep -A1 -xF -- --add-dir "$SB/log/claude.args" | tail -1)"
check "without tool flags none are passed" "0" \
  "$(grep -cE '^--(allowed|disallowed)Tools$' "$SB/log/claude.args" || true)"
rm -rf "$SB"

echo
if [[ $fails -eq 0 ]]; then
  echo "all orchestrator tests passed"
else
  echo "$fails orchestrator test(s) failed"
  exit 1
fi
