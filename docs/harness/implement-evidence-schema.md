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
  "agent": {                             // the headless run's summary.json; null if missing
    "status": "completed",               // "completed" | "failed"
    "turns": 40,
    "cost_usd": 1.2
  },
  "diff": {                              // against merge_base; null without one
    "files_changed": 4,
    "insertions": 120,
    "deletions": 3,
    "changed_files": ["…"]
  },
  "checks": [
    {
      "name": "biome",
      "command": "yarn biome check …",
      "source": "always",                // run on every branch, whatever the plan says
      "exit_code": 0,                    // null if the check could not be run
      "log_tail": "…"                    // last 40 lines of combined output
    }
  ]
}
```

## Field notes

**`checks[].exit_code`** is `null` when there was nothing to run the check on —
biome with no changed files, for instance. That is recorded rather than omitted
so the gap is visible in the verdict.

**`agent`** is a fact about the session, not evidence about the code. A session
that hit its turn limit can still leave correct commits; the verdict marks it red
so a human looks, and the checks say whether the commits hold up.

## Verdict

`implement-verdict.sh` prints `{verdict, labels, reasons, evidence_block}`.
`verdict` is `green` only when every rule passes; `red` carries
`labels: ["agent:needs-help"]` and one reason per failed rule. `evidence_block`
is Markdown wrapped in `<!-- evidence:start -->` / `<!-- evidence:end -->`, so a
later run can replace it in a PR body without touching the rest.
