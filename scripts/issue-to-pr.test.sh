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

  # claude: records its flags and stdin, then acts out FAKE_CLAUDE in its cwd.
  cat > "$sb/bin/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_LOG/claude.args"
cat > "$FAKE_LOG/claude.stdin"
pwd > "$FAKE_LOG/claude.cwd"
case "${FAKE_CLAUDE:-commit}" in
  commit|fail)
    echo "export const x = 1;" > thing.ts
    git add thing.ts && git -c user.email=a@b -c user.name=agent commit --quiet -m "feat: thing" ;;
esac
if [[ "${FAKE_CLAUDE:-commit}" == "fail" ]]; then
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
check "the agent was told not to push or open a PR" "yes" \
  "$(grep -q 'do not push and do not open a pull request' "$SB/log/claude.stdin" && echo yes || echo no)"
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
check "the evidence records the commit" "1" "$(jq '.commits' "$SB/runs/issue-7/evidence.json")"
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

echo
if [[ $fails -eq 0 ]]; then
  echo "all orchestrator tests passed"
else
  echo "$fails orchestrator test(s) failed"
  exit 1
fi
