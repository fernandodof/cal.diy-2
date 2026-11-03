#!/usr/bin/env bash
# Turn a GitHub issue into a draft pull request carrying evidence the harness
# gathered itself.
#
# The agent implements the issue in its own worktree and only commits. This
# script then re-runs the checks (scripts/implement-evidence.sh), judges them
# (scripts/implement-verdict.sh), pushes the branch and opens the PR — so nothing
# in the PR's evidence comes from the agent's own report.
#
# Before any branch exists it refuses an issue the repo owner did not write
# (unless --trust) and one the ambiguity judge cannot work from. Once past them,
# it removes the worktrees of issues whose PR was merged or closed.
#
# Usage:
#   ./scripts/issue-to-pr.sh 42
#   ./scripts/issue-to-pr.sh --trust 42     # an issue someone else wrote
#
# The PR targets main unless the issue names another base, with a
# `base:<branch>` label or a `Base: <branch>` line in its body.
#
# Exit codes: 0 = draft PR opened, evidence green; 1 = red (PR opened if there was
# anything to push); 2 = bad usage/environment, or another run on the issue is
# going; 3 = refused (untrusted author or ambiguous issue), nothing created.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${HEADLESS_TASK_OUT_DIR:-$REPO_ROOT/.claude/headless-runs}"
WORKTREE_DIR="${ISSUE_TO_PR_WORKTREE_DIR:-$(dirname "$REPO_ROOT")/$(basename "$REPO_ROOT")-worktrees}"
BASE_REF="main"
ISSUE=""
TRUST=false

usage() {
  sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trust) TRUST=true; shift ;;
    -h|--help) usage ;;
    -*) echo "issue-to-pr: unknown option $1" >&2; usage ;;
    *) ISSUE="$1"; shift ;;
  esac
done

[[ "$ISSUE" =~ ^[0-9]+$ ]] || usage

for cmd in gh jq git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "issue-to-pr: \`$cmd\` is not on PATH" >&2
    exit 2
  }
done

# Per-phase turn caps and one cost cap for the whole run. Every session is
# started with what is left of the cost cap, so the cap holds inside a session
# and not only between them — to within one turn: the CLI checks its budget
# between turns, so a run can end up to a turn's cost over the cap.
MAX_COST_USD="${HEADLESS_TASK_MAX_COST_USD:-5}"
MAX_TURNS_RESEARCH="${HEADLESS_TASK_MAX_TURNS_RESEARCH:-30}"
MAX_TURNS_PLAN="${HEADLESS_TASK_MAX_TURNS_PLAN:-15}"
MAX_TURNS_IMPLEMENT="${HEADLESS_TASK_MAX_TURNS_IMPLEMENT:-80}"
MAX_TURNS_REVIEW="${HEADLESS_TASK_MAX_TURNS_REVIEW:-30}"
MAX_TURNS_FIX="${HEADLESS_TASK_MAX_TURNS_FIX:-40}"
for cap in "$MAX_TURNS_RESEARCH" "$MAX_TURNS_PLAN" "$MAX_TURNS_IMPLEMENT" "$MAX_TURNS_REVIEW" "$MAX_TURNS_FIX"; do
  [[ "$cap" =~ ^[1-9][0-9]*$ ]] || { echo "issue-to-pr: turn cap '$cap' is not a positive whole number" >&2; exit 2; }
done
[[ "$MAX_COST_USD" =~ ^[0-9]+(\.[0-9]+)?$ ]] && jq -en --argjson c "$MAX_COST_USD" '$c > 0' >/dev/null \
  || { echo "issue-to-pr: cost cap '$MAX_COST_USD' is not a positive number of dollars" >&2; exit 2; }

RUN_ID="issue-$ISSUE"
RUN_DIR="$OUT_DIR/$RUN_ID"
BRANCH="agent/issue-$ISSUE"
WORKTREE="$WORKTREE_DIR/$RUN_ID"

# One run per issue at a time: two would share its branch, worktree and run
# directory. mkdir is atomic, so only one run creates the lock. A lock whose run
# has died is taken over; one with no pid yet may be a run that is just starting.
LOCK="$OUT_DIR/$RUN_ID.lock"
mkdir -p "$OUT_DIR"
if ! mkdir "$LOCK" 2>/dev/null; then
  LOCK_PID="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [[ -z "$LOCK_PID" ]] || kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "issue-to-pr: another run on #$ISSUE holds $LOCK (pid ${LOCK_PID:-unknown}); remove it if no run is going" >&2
    exit 2
  fi
  echo "issue-to-pr: taking over the lock of a run that died (pid $LOCK_PID)" >&2
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

# A run directory holds one run: older files beside the new ones read as this
# run's. An earlier run's is kept beside it, since this one may yet be refused.
[[ -d "$RUN_DIR" ]] && mv "$RUN_DIR" "$RUN_DIR-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN_DIR"

gh issue view "$ISSUE" --json number,title,body,url,author,labels > "$RUN_DIR/issue.json" 2>/dev/null || {
  echo "issue-to-pr: could not fetch issue #$ISSUE (not found, or gh is not authenticated)" >&2
  exit 2
}

# --- trust gate -------------------------------------------------------------
# The issue body becomes the agent's prompt, so only the owner's issues run
# unasked. Refusing costs nothing and writes nothing, so it comes first.
OWNER="$(gh repo view --json owner --jq '.owner.login' 2>/dev/null)" || {
  echo "issue-to-pr: could not read the repo owner" >&2
  exit 2
}
AUTHOR="$(jq -r '.author.login // ""' "$RUN_DIR/issue.json")"
if [[ "$AUTHOR" != "$OWNER" && "$TRUST" != true ]]; then
  echo "issue-to-pr: refused — #$ISSUE was written by '${AUTHOR:-unknown}', not the repo owner '$OWNER'." >&2
  echo "issue-to-pr: read it, then pass --trust to run it anyway" >&2
  exit 3
fi
# The author is not the whole of it: whoever last edited the body wrote what the
# agent will read. Unknown is not "nobody", so a failed lookup stops the run.
EDITOR_LOGIN="$(gh api graphql -F owner='{owner}' -F name='{repo}' -F number="$ISSUE" \
  -f query='query($owner: String!, $name: String!, $number: Int!) { repository(owner: $owner, name: $name) { issue(number: $number) { editor { login } } } }' \
  --jq '.data.repository.issue.editor.login // ""' 2>/dev/null)" || {
  echo "issue-to-pr: could not read who last edited #$ISSUE" >&2
  exit 2
}
if [[ -n "$EDITOR_LOGIN" && "$EDITOR_LOGIN" != "$OWNER" && "$TRUST" != true ]]; then
  echo "issue-to-pr: refused — #$ISSUE was last edited by '$EDITOR_LOGIN', not the repo owner '$OWNER'." >&2
  echo "issue-to-pr: read it, then pass --trust to run it anyway" >&2
  exit 3
fi

# --- base branch ------------------------------------------------------------
# main, unless the issue names another. Every later use of the base — the
# worktree cut, the phase prompts, the evidence diff, the PR — reads BASE_REF.
BASES=()
while IFS= read -r candidate; do
  [[ -n "$candidate" ]] && ! printf '%s\n' ${BASES[@]+"${BASES[@]}"} | grep -qxF -- "$candidate" \
    && BASES+=("$candidate")
done < <(
  jq -r '(.labels // [])[].name | select(startswith("base:")) | ltrimstr("base:")' "$RUN_DIR/issue.json"
  jq -r '.body // ""' "$RUN_DIR/issue.json" | tr -d '\r' | sed -n -E 's/^Base: *`?([^` ]+)`? *$/\1/p'
)
if [[ ${#BASES[@]} -gt 1 ]]; then
  # Guessing between two bases is how the PR ends up on the wrong one.
  echo "issue-to-pr: #$ISSUE names more than one base ($(IFS=', '; echo "${BASES[*]}")); keep one" >&2
  exit 2
fi
[[ ${#BASES[@]} -eq 1 ]] && BASE_REF="${BASES[0]}"

# The issue's author chose this name, and it reaches git and the agent's prompt.
# git's own check is not enough on its own: it accepts `x;rm`.
if [[ ! "$BASE_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || ! git check-ref-format --branch "$BASE_REF" >/dev/null 2>&1; then
  echo "issue-to-pr: '$BASE_REF' is not a branch name the harness will use as a base" >&2
  exit 2
fi
if [[ "$BASE_REF" == "$BRANCH" ]]; then
  echo "issue-to-pr: the base cannot be the working branch $BRANCH itself" >&2
  exit 2
fi
# No fallback to main: a PR against the wrong base is worse than none.
if ! git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$BASE_REF" >/dev/null 2>&1; then
  echo "issue-to-pr: base '$BASE_REF' does not exist on origin" >&2
  exit 2
fi
echo "issue-to-pr: base $BASE_REF" >&2

# --- labels -----------------------------------------------------------------
# Created on first use, so a fresh fork needs no setup. Existing labels are left
# as they are: someone may have recoloured or described them.
EXISTING_LABELS="$(gh label list --limit 200 --json name --jq '.[].name')"
while IFS='|' read -r name color description; do
  grep -qxF "$name" <<<"$EXISTING_LABELS" && continue
  gh label create "$name" --color "$color" --description "$description" >/dev/null
done <<'LABELS'
agent:implement|5319E7|Hand this issue to the issue-to-PR harness
agent:needs-clarification|FBCA04|Too ambiguous for the harness to implement as written
agent:needs-help|D93F0B|The harness opened this PR, but its evidence is red
LABELS

# --- ambiguity gate ---------------------------------------------------------
# The scorer's rubric runs 3 (unambiguous) down to 0 (unactionable). At 1 or
# below a contributor would have to guess the key decision, so the issue goes
# back to its author with the judge's reasoning before any work starts.
SCORER="${ISSUE_TO_PR_SCORER:-$REPO_ROOT/evals/issue-ambiguity/score.sh}"
"$SCORER" --issue "$(gh repo view --json nameWithOwner --jq '.nameWithOwner')#$ISSUE" \
  > "$RUN_DIR/ambiguity.json" 2>/dev/null || true
SCORE="$(jq -r '.score // "null"' "$RUN_DIR/ambiguity.json" 2>/dev/null || echo null)"
REASONING="$(jq -r '.reasoning // ""' "$RUN_DIR/ambiguity.json" 2>/dev/null || true)"

# A judge that did not answer has said nothing about the issue.
if [[ ! "$SCORE" =~ ^[0-3]$ ]]; then
  echo "issue-to-pr: the ambiguity scorer gave no score; see $RUN_DIR/ambiguity.json" >&2
  exit 2
fi

if [[ "$SCORE" -le 1 ]]; then
  # One comment per version of the issue's text: a re-run on an unchanged issue
  # would only repeat it. A failed lookup posts anyway, rather than refuse silently.
  MARKER="<!-- issue-to-pr:ambiguity $(jq -j '.title + "\n" + (.body // "")' "$RUN_DIR/issue.json" | git hash-object --stdin) -->"
  if gh issue view "$ISSUE" --json comments 2>/dev/null \
    | jq -e --arg marker "$MARKER" '.comments // [] | any(.body | contains($marker))' >/dev/null 2>&1; then
    echo "issue-to-pr: #$ISSUE already has this verdict on its current text; not commenting again" >&2
  else
    gh issue comment "$ISSUE" --body "$(cat <<COMMENT
The issue-to-PR harness did not start on this issue: it scored **$SCORE / 3** for clarity, where 2 is the least it works from.

> $REASONING

Once the issue answers that, re-run \`./scripts/issue-to-pr.sh $ISSUE\`. The scale is in \`evals/issue-ambiguity/RUBRIC.md\`.

$MARKER
COMMENT
)" >/dev/null
  fi
  gh issue edit "$ISSUE" --add-label agent:needs-clarification >/dev/null
  echo "issue-to-pr: refused — #$ISSUE scored $SCORE/3 for clarity: $REASONING" >&2
  exit 3
fi

# Clear enough now: drop the label an earlier, vaguer version of the issue earned.
if jq -e '.labels // [] | any(.name == "agent:needs-clarification")' "$RUN_DIR/issue.json" >/dev/null; then
  gh issue edit "$ISSUE" --remove-label agent:needs-clarification >/dev/null
fi

# --- cleanup ----------------------------------------------------------------
# Each worktree holds several GB of node_modules. One whose PR was merged or
# closed has nothing left to do, so it goes; its branch stays, and a re-run
# re-attaches it. Kept: a worktree another run holds the lock on, one whose PR
# state can't be read, and one with uncommitted changes, which git refuses to remove.
# git lists worktrees by their physical path, symlinks resolved (/var is
# /private/var on macOS).
WORKTREE_DIR_PHYSICAL="$(cd "$WORKTREE_DIR" 2>/dev/null && pwd -P || true)"
[[ -n "$WORKTREE_DIR_PHYSICAL" ]] && git -C "$REPO_ROOT" worktree list --porcelain \
  | awk '/^worktree /{path = substr($0, 10)} /^branch refs\/heads\/agent\/issue-[0-9]+$/{print path "\t" substr($0, 19)}' \
  | while IFS=$'\t' read -r old_worktree old_branch; do
      [[ "$old_branch" != "$BRANCH" && "$old_worktree" == "$WORKTREE_DIR_PHYSICAL/"* ]] || continue
      [[ -d "$OUT_DIR/issue-${old_branch#agent/issue-}.lock" ]] && continue
      state="$(gh pr list --head "$old_branch" --state all --json state \
        --jq 'if any(.state == "OPEN") then "open" else (.[0].state // "" | ascii_downcase) end' 2>/dev/null || true)"
      [[ "$state" == merged || "$state" == closed ]] || continue
      if git -C "$REPO_ROOT" worktree remove "$old_worktree" 2>/dev/null; then
        echo "issue-to-pr: removed $old_worktree, whose PR is $state" >&2
      else
        echo "issue-to-pr: kept $old_worktree: its PR is $state, but it has uncommitted changes" >&2
      fi
    done

# --- worktree ---------------------------------------------------------------
git -C "$REPO_ROOT" fetch --quiet origin "$BASE_REF"
# A branch that exists is a run to continue: its gate files say how far it got.
RESUMING=false
LOCAL_BRANCH=false
REMOTE_BRANCH=false
git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null && LOCAL_BRANCH=true
git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1 && REMOTE_BRANCH=true
mkdir -p "$WORKTREE_DIR"
if [[ "$LOCAL_BRANCH" == true || "$REMOTE_BRANCH" == true ]]; then
  RESUMING=true
  if [[ "$REMOTE_BRANCH" == true ]]; then
    git -C "$REPO_ROOT" fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
    [[ "$LOCAL_BRANCH" == true ]] || git -C "$REPO_ROOT" branch --quiet "$BRANCH" "origin/$BRANCH"
  fi
  # A worktree directory someone deleted is still registered until pruned.
  git -C "$REPO_ROOT" worktree prune
  if [[ -d "$WORKTREE" ]]; then
    [[ "$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$BRANCH" ]] || {
      echo "issue-to-pr: $WORKTREE exists but is not on $BRANCH" >&2
      exit 2
    }
  else
    git -C "$REPO_ROOT" worktree add --quiet "$WORKTREE" "$BRANCH"
  fi
  # Take in what a person pushed; never rewrite what they pushed.
  if [[ "$REMOTE_BRANCH" == true ]] && ! git -C "$WORKTREE" merge --quiet --ff-only "origin/$BRANCH" >/dev/null 2>&1; then
    echo "issue-to-pr: $BRANCH has diverged from origin/$BRANCH; reconcile them, then re-run" >&2
    exit 2
  fi
  echo "issue-to-pr: resuming $BRANCH in $WORKTREE" >&2
else
  git -C "$REPO_ROOT" worktree add --quiet -b "$BRANCH" "$WORKTREE" "origin/$BASE_REF"
  echo "issue-to-pr: worktree $WORKTREE on $BRANCH" >&2
fi

# The worktree needs its own install. Workspace packages are linked relatively
# (node_modules/@calcom/* -> ../../packages/*), so borrowing this checkout's
# node_modules would resolve them here, and the evidence would test the wrong
# code. Reusing this checkout's cache keeps the install offline.
echo "issue-to-pr: installing dependencies in the worktree" >&2
(cd "$WORKTREE" && YARN_CACHE_FOLDER="$REPO_ROOT/.yarn/cache" yarn install --immutable) \
  > "$RUN_DIR/install.log" 2>&1 || {
  echo "issue-to-pr: yarn install failed in $WORKTREE; see $RUN_DIR/install.log" >&2
  exit 2
}

# --- agent sessions ---------------------------------------------------------
# What the agent may run: enough to implement and verify its own work, which the
# #11 run was denied. Pushing and opening PRs are the harness's, and so is GitHub:
# `gh issue view` also reads comments, other issues and other repos, none of which
# the trust gate saw. The deny list keeps both that way even if the allow list or
# permission mode is loosened.
ALLOWED_TOOLS="Read,Edit,Write,Glob,Grep,Skill"
ALLOWED_TOOLS+=",Bash(yarn test:*),Bash(yarn biome:*),Bash(yarn turbo run type-check:*),Bash(yarn tsc --noEmit -p:*)"
ALLOWED_TOOLS+=",Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git add:*),Bash(git commit:*)"
ALLOWED_TOOLS+=",Bash(ls:*),Bash(cat:*),Bash(grep:*),Bash(find:*)"
DISALLOWED_TOOLS="Bash(git push:*),Bash(gh:*)"

ISSUE_URL="$(jq -r '.url' "$RUN_DIR/issue.json")"
SPEC=""

# The spec folder is the agent's choice — Phase 1 may extend an existing one —
# so it is found from what the branch added, not predicted. More than one
# candidate is as good as none.
resolve_spec() {
  local found
  found="$(git -C "$WORKTREE" diff --name-only --diff-filter=A "origin/$BASE_REF" HEAD -- 'specs/*/gates/1-research.md')"
  [[ -n "$found" && "$(wc -l <<<"$found")" -eq 1 ]] && dirname "$(dirname "$found")"
}

# One session per phase, each reading only the previous phase's handoff file.
# Every session's summary goes into the evidence as a fact; whether the sequence
# should have stopped is judged there, not here.
# Standards findings and scope creep are the reviewer's to weigh; a spec
# requirement that is missing or wrong is the one thing worth a second pass.
review_wants_fix() {
  jq -e '.findings | any(.axis == "spec" and (.kind == "missing" or .kind == "wrong"))' \
    "$WORKTREE/.agent-handoff/review.json" >/dev/null 2>&1
}

# Whether a phase finished in an earlier run of this branch. The fix round runs
# once per issue, whatever its outcome; a review stands until something is
# committed after it, except the fix round's own commits, which never get one.
phase_done() {
  local gate="$WORKTREE/$SPEC/gates/$1.md" reviewed
  [[ -n "$SPEC" && -f "$gate" ]] || return 1
  [[ "$1" == fix ]] && return 0
  [[ "$(head -1 "$gate")" == "Outcome: continue" ]] || return 1
  [[ "$1" == 4-review ]] || return 0
  jq -e '.findings | type == "array"' "$WORKTREE/.agent-handoff/review.json" >/dev/null 2>&1 || return 1
  [[ -f "$WORKTREE/$SPEC/gates/fix.md" ]] && return 0
  reviewed="$(git -C "$WORKTREE" log -1 --format=%H -- "$SPEC/gates/4-review.md")"
  [[ -n "$reviewed" && "$(git -C "$WORKTREE" rev-list --count "$reviewed..HEAD")" -eq 0 ]]
}

[[ "$RESUMING" == true ]] && SPEC="$(resolve_spec || true)"
: > "$RUN_DIR/phases.jsonl"
n=0
# A resumed run skips the phases already done, up to the first that is not;
# from there every phase runs, since each reads the one before it.
SKIPPING="$RESUMING"
# The fix round is not in the list: it runs at most once, after the review, and
# only when the review found a requirement missing or wrong.
FIX_PENDING=false
for phase in 1-research 2-plan 3-implement 4-review fix; do
  if [[ "$phase" == fix ]]; then
    [[ "$FIX_PENDING" == true ]] || break
    n=fix
  else
    n=$((n + 1))
  fi
  if { [[ "$SKIPPING" == true ]] || [[ "$phase" == fix ]]; } && phase_done "$phase"; then
    echo "issue-to-pr: phase $phase was done in an earlier run" >&2
    jq -nc --arg phase "$phase" \
      '{phase: $phase, status: "completed", subtype: "earlier_run", turns: null, cost_usd: null, outcome: "continue"}' \
      >> "$RUN_DIR/phases.jsonl"
    [[ "$phase" == 4-review ]] && review_wants_fix && FIX_PENDING=true
    continue
  fi
  SKIPPING=false
  TASK="/implement-task --headless --phase $n --base $BASE_REF $ISSUE_URL${SPEC:+ --spec $SPEC}"
  # The issue as the trust gate approved it, for the phases that read the issue.
  if [[ "$phase" == 1-research || "$phase" == 4-review ]]; then
    TASK+="$(jq -r '"\n\n# Issue #\(.number): \(.title)\n\n" + (.body // "(no description)")' "$RUN_DIR/issue.json")"
  fi
  case "$phase" in
    1-research) TURNS="$MAX_TURNS_RESEARCH" ;;
    2-plan) TURNS="$MAX_TURNS_PLAN" ;;
    3-implement) TURNS="$MAX_TURNS_IMPLEMENT" ;;
    4-review) TURNS="$MAX_TURNS_REVIEW" ;;
    fix) TURNS="$MAX_TURNS_FIX" ;;
  esac
  # /code-review runs its two axes as sub-agents; only the review needs them.
  PHASE_TOOLS="$ALLOWED_TOOLS"
  [[ "$phase" == 4-review ]] && PHASE_TOOLS+=",Agent"
  REMAINING="$(jq -s --argjson cap "$MAX_COST_USD" '$cap - (map(.cost_usd // 0) | add // 0)' "$RUN_DIR/phases.jsonl")"
  if jq -en --argjson r "$REMAINING" '$r <= 0' >/dev/null; then
    echo "issue-to-pr: stopping before phase $phase — the \$$MAX_COST_USD cost cap is spent" >&2
    break
  fi
  echo "issue-to-pr: phase $phase (up to $TURNS turns, \$$REMAINING left)" >&2
  printf '%s' "$TASK" | "$REPO_ROOT/scripts/headless-task.sh" \
    --run-id "$RUN_ID/$phase" --workdir "$WORKTREE" \
    --allowed-tools "$PHASE_TOOLS" --disallowed-tools "$DISALLOWED_TOOLS" \
    --max-turns "$TURNS" --max-budget-usd "$REMAINING" \
    - >/dev/null 2>&1 || true

  [[ "$phase" == 1-research ]] && SPEC="$(resolve_spec || true)"
  OUTCOME=""
  if [[ -n "$SPEC" && -f "$WORKTREE/$SPEC/gates/$phase.md" ]]; then
    [[ "$(head -1 "$WORKTREE/$SPEC/gates/$phase.md")" =~ ^Outcome:\ (continue|blocked)$ ]] \
      && OUTCOME="${BASH_REMATCH[1]}"
  fi
  jq -c --arg phase "$phase" --arg outcome "$OUTCOME" \
    '{phase: $phase, status, subtype, turns, cost_usd, outcome: (if $outcome == "" then null else $outcome end)}' \
    "$RUN_DIR/$phase/summary.json" >> "$RUN_DIR/phases.jsonl" 2>/dev/null \
    || jq -nc --arg phase "$phase" '{phase: $phase, status: null, subtype: null, turns: null, cost_usd: null, outcome: null}' >> "$RUN_DIR/phases.jsonl"

  # The next phase reads this one's handoff file, so it cannot start on a phase
  # that failed, blocked, or left no gate saying it finished.
  if [[ "$(jq -r '.status' "$RUN_DIR/$phase/summary.json" 2>/dev/null)" != "completed" || "$OUTCOME" != "continue" ]]; then
    echo "issue-to-pr: stopping after phase $phase (session $(jq -r '.status // "missing"' "$RUN_DIR/$phase/summary.json" 2>/dev/null || echo missing), gate ${OUTCOME:-missing})" >&2
    break
  fi
  [[ "$phase" == 4-review ]] && review_wants_fix && FIX_PENDING=true
  # A plan marked blocked is a stop on its own, whatever the gate file says.
  if [[ -n "$SPEC" ]] && grep -qE '^## Status: blocked[[:space:]]*$' "$WORKTREE/$SPEC/implementation.md" 2>/dev/null; then
    echo "issue-to-pr: stopping after phase $phase — $SPEC/implementation.md says blocked" >&2
    break
  fi
done
jq -s . "$RUN_DIR/phases.jsonl" > "$RUN_DIR/phases.json"
jq -n --argjson cost "$MAX_COST_USD" \
  --argjson research "$MAX_TURNS_RESEARCH" --argjson plan "$MAX_TURNS_PLAN" --argjson implement "$MAX_TURNS_IMPLEMENT" \
  --argjson review "$MAX_TURNS_REVIEW" --argjson fix "$MAX_TURNS_FIX" \
  '{cost_cap_usd: $cost, turn_caps: {"1-research": $research, "2-plan": $plan, "3-implement": $implement, "4-review": $review, "fix": $fix}}' \
  > "$RUN_DIR/budget.json"

# --- evidence and verdict ---------------------------------------------------
"$REPO_ROOT/scripts/implement-evidence.sh" \
  --worktree "$WORKTREE" --base "$BASE_REF" \
  --issue-json "$RUN_DIR/issue.json" --phases "$RUN_DIR/phases.json" --budget "$RUN_DIR/budget.json" \
  ${SPEC:+--spec "$SPEC"} \
  > "$RUN_DIR/evidence.json"

set +e
"$REPO_ROOT/scripts/implement-verdict.sh" --evidence "$RUN_DIR/evidence.json" > "$RUN_DIR/verdict.json"
VERDICT_STATUS=$?
set -e
[[ $VERDICT_STATUS -le 1 ]] || exit 2
VERDICT="$(jq -r '.verdict' "$RUN_DIR/verdict.json")"

# A branch with nothing on it cannot back a PR. The verdict already says why;
# say it here too, since there is no PR to carry it.
if [[ "$(jq -r '.commits // 0' "$RUN_DIR/evidence.json")" -eq 0 ]]; then
  echo "issue-to-pr: red — the agent made no commits, so there is no PR to open" >&2
  jq -r '.reasons[] | "  - " + .' "$RUN_DIR/verdict.json" >&2
  exit 1
fi

# --- pull request -----------------------------------------------------------
git -C "$WORKTREE" push --quiet -u origin "$BRANCH"

DRAFT="$WORKTREE/.agent-handoff/pr-body.md"
{
  # The draft may close the issue itself; GitHub needs it said once.
  grep -qx "Closes #$ISSUE" "$DRAFT" 2>/dev/null || { echo "Closes #$ISSUE"; echo; }
  if [[ -f "$DRAFT" ]]; then
    cat "$DRAFT"
  elif [[ -n "$SPEC" && -f "$WORKTREE/$SPEC/gates/3-implement.md" ]]; then
    echo "_The agent left no PR body draft in \`.agent-handoff/pr-body.md\`. If it wrote one elsewhere, look in \`$SPEC/gates/3-implement.md\`._"
  else
    echo "_The agent left no PR body draft; the evidence below is all there is._"
  fi
  echo
  if [[ -n "$SPEC" ]]; then
    echo "### Gates"
    echo
    for gate in "$WORKTREE/$SPEC"/gates/*.md; do
      [[ -f "$gate" ]] && echo "- \`$SPEC/gates/$(basename "$gate")\` — $(head -1 "$gate")"
    done
    echo
  fi
  jq -r '.evidence_block' "$RUN_DIR/verdict.json"
  echo
  echo "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
} > "$RUN_DIR/pr-body.md"

# A branch with an open PR keeps it: only the evidence block is replaced, since
# the rest of the body may have been edited by hand since the PR was opened.
OPEN_PR="$(gh pr list --head "$BRANCH" --state open --json number,url,body,labels | jq -c '.[0] // empty')"
if [[ -n "$OPEN_PR" ]]; then
  jq -j --arg block "$(jq -r '.evidence_block' "$RUN_DIR/verdict.json")" '
    "<!-- evidence:start -->" as $start | "<!-- evidence:end -->" as $end
    | (.body | split($start)) as $parts
    | if ($parts | length) > 1 and ($parts[1:] | join($start) | contains($end)) then
        ($parts[1:] | join($start) | split($end)) as $rest
        | $parts[0] + $block + ($rest[1:] | join($end))
      else .body + "\n\n" + $block end' <<<"$OPEN_PR" > "$RUN_DIR/pr-body.md"
  LABEL_ARGS=()
  if [[ "$VERDICT" == red ]]; then
    LABEL_ARGS+=(--add-label agent:needs-help)
  elif jq -e '.labels // [] | any(.name == "agent:needs-help")' <<<"$OPEN_PR" >/dev/null; then
    LABEL_ARGS+=(--remove-label agent:needs-help)
  fi
  gh pr edit "$(jq -r '.number' <<<"$OPEN_PR")" --body-file "$RUN_DIR/pr-body.md" \
    ${LABEL_ARGS[@]+"${LABEL_ARGS[@]}"} >/dev/null
  PR_URL="$(jq -r '.url' <<<"$OPEN_PR")"
else
  LABEL_ARGS=()
  while IFS= read -r label; do
    [[ -n "$label" ]] && LABEL_ARGS+=(--label "$label")
  done < <(jq -r '.labels[]' "$RUN_DIR/verdict.json")

  PR_URL="$(gh pr create --draft --base "$BASE_REF" --head "$BRANCH" \
    --title "$(jq -r '.title' "$RUN_DIR/issue.json")" \
    --body-file "$RUN_DIR/pr-body.md" \
    ${LABEL_ARGS[@]+"${LABEL_ARGS[@]}"})"
fi

echo "issue-to-pr: $VERDICT — $PR_URL" >&2
echo "$PR_URL"
[[ "$VERDICT" == "green" ]]
