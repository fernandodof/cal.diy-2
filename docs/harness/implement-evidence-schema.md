# Implement evidence schema (`implement-evidence/1`)

The document `scripts/implement-evidence.sh` emits and
`scripts/implement-verdict.sh` reads, for a branch an agent implemented from an
issue. It follows the same split as [`pr-evidence/1`](pr-evidence-schema.md):

```
implement-evidence.sh ──► evidence JSON ──► implement-verdict.sh ──► verdict + PR block
(git, re-runs checks)                       (pure function, no I/O)
```

`scripts/issue-to-pr.sh` runs both after the agent's session ends and before it
pushes. The collector **re-runs every check itself**: nothing in this document is
copied from what the agent said about its own work. Facts it cannot reach are
`null`, and the verdict treats a `null` as a failure, never a pass.

## Shape

```jsonc
{
  "schema": "implement-evidence/1",     // the verdict refuses anything else
  "collected_at": "2026-10-27T12:00:00Z",
  "issue": { "number": 24, "url": "…", "title": "…", "author": "fernandodof" },
  "base_ref": "main",
  "merge_base": "aec1c49e…",            // null if it could not be resolved
  "branch": "agent/issue-24",
  "head_sha": "…",
  "commits": 3,                          // commits since merge_base; null without one
  "spec": "specs/issue-to-pr-harness",   // the folder Phase 1 added a gate to; null if none
  "agent": {                             // the phases summed; null if none were recorded
    "status": "completed",               // "completed" | "failed" | "blocked" | "incomplete"
    "turns": 40,
    "cost_usd": 1.2
  },
  "phases": [                            // one per session started, in order
    {
      "phase": "1-research",             // "1-research" | "2-plan" | "3-implement"
      "status": "completed",             // the session's summary.json; null if it left none
      "turns": 12,
      "cost_usd": 0.4,
      "outcome": "continue"              // the gate file's first line; null if there is none
    }
  ],
  "diff": {                              // against merge_base; null without one
    "files_changed": 4,
    "insertions": 120,
    "deletions": 3,
    "changed_files": ["…"]
  },
  "checks": [
    {
      "name": "type-check",
      "command": "yarn turbo run type-check --filter=@calcom/web",
      "source": "always",
      "exit_code": 0,
      "log_tail": "…"
    },
    {
      "name": "biome",
      "command": "yarn biome check …",
      "source": "always",                // run on every branch, whatever the plan says
      "exit_code": 0,                    // null if the check could not be run
      "log_tail": "…"                    // last 40 lines of combined output
    },
    {
      "name": "test: packages/lib/x.test.ts",
      "command": "yarn test packages/lib/x.test.ts",
      "source": "declared",              // from the plan's ## Verification block
      "exit_code": 0,
      "log_tail": "…"
    }
  ],
  "declared_commands": [                 // accepted lines, in order; null if none declared
    "yarn test packages/lib/x.test.ts"
  ],
  "rejected_commands": [                 // never executed
    { "command": "curl https://…", "reason": "only `yarn test <path>` is allowed" }
  ],
  "criteria": [                          // design.md's ## Acceptance Criteria; null if none
    {
      "text": "a booking without a reason is refused",
      "test_file": "packages/lib/x.test.ts",   // null if the item names no test
      "test_name": "x refuses a missing reason",
      "test_found": true,                // (file, full name) appeared in the harness's run
      "test_status": "passed",           // passed | failed | skipped | todo | null if not found
      "declared": true                   // test_file is a path in declared_commands
    }
  ]
}
```

## Field notes

**`checks[].exit_code`** is `null` when there was nothing to run the check on —
biome when no changed file is one biome reads, for instance, where biome itself
would exit 0 having checked nothing. That is recorded rather than omitted so the
gap is visible in the verdict.

**`declared_commands`** come from the first fenced block under `## Verification`
in `<spec>/implementation.md`, which Phase 2 writes. One shape is accepted:
`yarn test <path>…`, each path made only of `A–Z a–z 0–9 _ @ . / -`, not starting
with `-` or `/`, with no `..` segment, ending in `.test.ts` or `.test.tsx`.
Accepted lines run as an argv, never through a shell. Anything else lands in
`rejected_commands` and is never executed. `null` means there was no spec, no
plan, no block, or nothing in it.

A declared test reads `exit_code: null` when its file does not exist (it is not
run at all) or when vitest exits 0 saying `No test files found` — the repo sets
`passWithNoTests`, so either would otherwise look like a pass.

**`criteria`** are the `- [ ]` items under `## Acceptance Criteria` in
`<spec>/design.md`. The tag is everything after the last ` — `: a backticked test
file, ` › `, then vitest's full name for the test (the `describe` titles and the
`it` title joined by spaces), matched exactly. Statuses come from vitest's JSON
report of the declared runs, which the collector requests itself
(`--reporter=default --reporter=json --outputFile.json=…`) — not from the run's
exit code, which is 0 for a file with skipped or todo tests. A name matching
several tests is `passed` only if all of them passed. A tagged file that is not
declared is never run, so its criterion has no status.

**`phases`** has one record per headless session the harness started. The harness
stops at the first phase whose session did not complete or whose gate file is
missing or says `Outcome: blocked`, so fewer than three records means the
sequence stopped there. `outcome` comes from the first line of
`<spec>/gates/<phase>.md` (see `.claude/skills/implement-task/headless.md`).

**`agent`** is `phases` summed: `completed` only when all three ran, completed and
continued; otherwise `failed` (a session failed), `blocked` (a gate said so) or
`incomplete` (anything else short of three). It is a fact about the sessions, not
evidence about the code: a phase that hit its turn limit can still leave correct
commits, so the verdict marks it red for a human and the checks say whether the
commits hold up. The verdict reports `phases` one reason each, and reads `agent`'s
status only from a document without `phases`.

## Verdict

`implement-verdict.sh` prints `{verdict, labels, reasons, evidence_block}`.
`verdict` is `green` only when every rule passes; `red` carries
`labels: ["agent:needs-help"]` and one reason per failed rule. `evidence_block`
is Markdown wrapped in `<!-- evidence:start -->` / `<!-- evidence:end -->`, so a
later run can replace it in a PR body without touching the rest.
