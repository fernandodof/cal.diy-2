# PR evidence schema (`pr-evidence/1`)

The document `scripts/pr-evidence.sh` emits and `scripts/pr-self-approval.sh`
reads. It is the seam between **gathering facts** and **judging them**:

```
pr-evidence.sh  ──► evidence JSON ──►  pr-self-approval.sh  ──► verdict
(gh, git, network)                     (pure function, no I/O)
```

Everything that needs the network lives on the left. Everything that encodes
[the policy](pr-self-approval-policy.md) lives on the right and can be tested
against a handwritten fixture — which is how
`scripts/pr-self-approval.test.sh` runs, with no GitHub and no git.

The collector never decides anything. It emits the same shape whether the PR is
perfect or a disaster, and reports unreachable facts as `null` rather than
guessing. Deciding what a `null` means is the policy's job, and it treats one as
a failed gate, never a pass.

## Shape

```jsonc
{
  "schema": "pr-evidence/1",          // policy refuses anything else
  "collected_at": "2026-09-29T12:00:00Z",
  "source_locale": "packages/i18n/locales/en/common.json",
  "locale_glob": "packages/i18n/locales/*/common.json",
  "merge_base": "aec1c49e…",          // null if it could not be resolved
  "pr": {
    "number": 13,
    "url": "https://github.com/…/pull/13",
    "title": "…",
    "author": "fernandodof",          // login, "" if unknown
    "is_draft": false,
    "head_sha": "…",
    "base_ref": "main",
    "changed_files": ["…"],           // every path in the PR, not just locales
    "changes_requested": 0,           // count of CHANGES_REQUESTED reviews
    "checks": [                       // normalised from statusCheckRollup
      { "name": "Linters / lint", "state": "SUCCESS" }
    ]
  },
  "en_before": { /* en/common.json at the merge base */ },  // null if unreadable
  "locales": [
    {
      "path": "packages/i18n/locales/pt-BR/common.json",
      "locale": "pt-BR",
      "after":  { /* the file at head */ },        // null if absent or unparseable
      "before": { /* the file at the merge base */ },
      "after_present": true,   // the blob exists at head
      "after_parsed":  true,   // …and it is valid JSON
      "before_parsed": true    // a new locale file is legitimately false
    }
  ]
}
```

## Field notes

**`checks[].state`** is normalised to one uppercase word. A `CheckRun` reports
`.conclusion` once it finishes and `.status` while it runs; a `StatusContext`
reports `.state`. All three collapse here, and anything unfinished becomes
`PENDING` rather than an empty string — a blank state made the policy print a
reason nobody could read.

**`locales`** holds one entry per changed *translation* file, with `en` itself
excluded (it is carried once as `en_before`). Non-translation files appear only
in `pr.changed_files`, which is what the scope gate reads.

**`after_present` vs `after_parsed`** separate two different failures: a blob
that is missing at head, and one that is there but malformed. The policy reports
them differently, and neither can be inferred from `after: null` alone.

**`before_parsed: false`** is normal for a locale file added by the PR. The
policy treats an absent `before` as "no prior state to compare against" and
skips the deletion check for that file rather than failing it.

## Adding a field

Additive changes keep `pr-evidence/1`: the policy reads what it needs and
ignores the rest. Renaming or removing a field, or changing what one means, is a
new schema version — bump it in both scripts, or the policy refuses the document
rather than silently misreading it.
