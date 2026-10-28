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
  )

  # gh: canned issue, recorded PR calls.
  cat > "$sb/bin/gh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG/gh.log"
case "$1 $2" in
  "issue view")
    jq -n --arg author "${FAKE_ISSUE_AUTHOR:-fernandodof}" \
      '{number: 7, title: "test(lib): cover a thing", body: "Add a test.",
        url: "https://example.test/issues/7", author: {login: $author}}' ;;
  "pr create") echo "https://example.test/pull/99" ;;
  "label list") printf '%s\n' ${FAKE_EXISTING_LABELS:-} ;;
  "label create"|"pr edit") ;;
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
    1) echo "# design" > specs/thing/design.md; gate 1-research ;;
    2) echo "# plan" > specs/thing/implementation.md; gate 2-plan ;;
    3)
      if [[ "$mode" == docs ]]; then echo "# notes" > notes.md; else echo "export const x = 1;" > thing.ts; fi
      gate 3-implement
      mkdir -p .claude/headless-runs
      printf '## What changed\n\nThe agent draft.\n' > .claude/headless-runs/pr-body.md ;;
  esac
  # Everything but the PR body draft, which headless.md says is never committed.
  git add -A -- . ':!.claude'
  git -c user.email=a@b -c user.name=agent commit --quiet -m "phase $phase"
fi
if [[ "${FAKE_FAIL_PHASE:-}" == "$phase" || ( "$mode" == fail && "$phase" == 3 ) ]]; then
  echo '{"is_error": true, "subtype": "error_max_turns", "num_turns": 40, "total_cost_usd": 1}'
else
  echo '{"is_error": false, "subtype": "success", "result": "Did the thing.", "num_turns": 3, "total_cost_usd": 0.1}'
fi
FAKE

  # yarn: records each call; FAKE_YARN_FAIL names a subcommand that exits 1.
  cat > "$sb/bin/yarn" <<'FAKE'
#!/usr/bin/env bash
echo "$* cwd=$PWD cache=${YARN_CACHE_FOLDER:-}" >> "$FAKE_LOG/yarn.log"
[[ -n "${FAKE_YARN_FAIL:-}" && "$*" == *"$FAKE_YARN_FAIL"* ]] && { echo "boom"; exit 1; }
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
    "$sb/repo/scripts/issue-to-pr.sh" 7 > "$sb/log/stdout" 2> "$sb/log/stderr"
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
check "the evidence carries both always-on checks" "type-check,biome" \
  "$(jq -r '[.checks[].name] | join(",")' "$SB/runs/issue-7/evidence.json")"
check "a second run refuses the existing branch" "2" "$(run "$SB")"
check "all three labels are created on first use" "3" "$(grep -c '^label create agent:' "$SB/log/gh.log")"
check "a green PR is not labelled" "0" "$(grep -c '^pr create .*--label' "$SB/log/gh.log")"
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
