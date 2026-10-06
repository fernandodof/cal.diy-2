# PR self-approval policy — translation changes

Many pull requests in this fork are written by an agent or by the lingo.dev bot
(`.github/workflows/i18n.yml`), and translation PRs are the highest-volume,
lowest-signal thing in the queue: a change across 44 locales in
`packages/i18n/locales/<lang>/common.json` is thousands of lines nobody will
read line by line. Reviewer attention is the scarce resource, and spending it
here is how it gets wasted.

So translations are where self-approval pays. This policy defines exactly when a
**translation-only** PR may be merged without a human reading the diff.

## How it is enforced

Three pieces, deliberately separate:

| | |
|---|---|
| `scripts/pr-evidence.sh` | Gathers the facts from GitHub and git. Decides nothing. |
| `scripts/pr-self-approval.sh` | Applies this document to those facts. Touches no network. |
| `.claude/skills/self-approval-check/` | Runs the pair and reports the verdict, on request. |
| `.github/workflows/translation-self-approval.yml` | Runs the pair on every locale PR, and approves the ones that pass. |

The seam between the first two is a JSON document — see
[pr-evidence-schema.md](pr-evidence-schema.md). Keeping them apart means this
policy can be tested against handwritten evidence with no network, and the same
evidence can be judged twice without being gathered twice.

## Scope

The policy applies only to PRs whose every changed file is a translation file:

```
packages/i18n/locales/<lang>/common.json
```

A PR touching anything else — one source file, one workflow, one doc — is out of
scope and is `needs-human`. This is deliberate: the reason a 3,000-line diff can
be merged unread is that its *shape* is known. Mix in a `.ts` file and that
argument collapses.

## Verdicts

| Verdict | Meaning |
|---|---|
| `auto-approve` | Every gate passed. Merge without a human reading the diff. |
| `needs-human` | At least one gate failed. A human reads the diff before merging. |

`needs-human` is a routing decision, not a rejection. Most translation PRs that
fail a gate are fine — they just need eyes.

## Gates

`auto-approve` requires **all** of the following. Any one failure routes to a
human.

### 1. Translation-only diff

Every changed file matches `packages/i18n/locales/*/common.json`. See Scope.

### 2. `en` is not modified

`packages/i18n/locales/en/common.json` is the source of truth that every other
locale is generated from. A machine changing English is changing the input, not
the output — that is a content decision and always gets a human.

### 3. Every changed file is valid JSON with a flat string shape

Each changed file must parse, and each of its values must be a string or a
nested object of strings. A translation file that has become an array, a number,
or `null` will fail at runtime in a locale nobody on the team reads.

### 4. No key is deleted, and no key is added that `en` lacks

Compare each changed locale against `en` at the merge base:

- **Deletions** — a key present before and absent after — mean a string
  disappears from the UI for that locale. Always a human.
- **Additions not present in `en`** mean a locale has invented a key the app
  never looks up. Harmless but wrong, and a signal the generator misfired.

Keys in `en` that a locale is still missing are **fine** — translation lags
source, and every locale here is already behind (`pt-BR` has 4,577 of `en`'s
4,735). The gate is about drift, not completeness.

### 5. No interpolation placeholder is lost

If a value in `en` contains `{{name}}`-style placeholders, the translated value
for that key must contain the same set. A dropped placeholder renders a literal
`{{name}}` — or an empty slot — to a real user. This is the single most common
way machine translation breaks a string, and the cheapest to catch.

### 6. CI is green

Every check on the head commit has concluded successfully. Pending, failing, or
cancelled fails the gate — an unfinished run is not evidence.

One exception, and only one: the enforcing workflow's own check is excluded.
It is a check on the PR it is judging, so it is always pending while it runs;
counting it would deadlock every PR, since the gate could never go green. Its
result *is* the verdict, not evidence for it. The excluded name is
`PR_SELF_APPROVAL_SELF_CHECK` (default `Self-approval check`) — and a PR whose
only check is that one still fails this gate, as having no CI at all.

### 7. Not a draft, no requested changes

A draft PR, or one carrying a `CHANGES_REQUESTED` review, is `needs-human` by
definition: someone has already said it is not ready.

### 8. The author is a trusted committer or the translation bot

An account with write access to the repo, or the lingo.dev app that
`.github/workflows/i18n.yml` runs as. A PR from outside that set — a drive-by
locale fix from a stranger, say — is read by a human regardless of content.

The allowed set lives in `PR_SELF_APPROVAL_AUTHORS` and
`PR_SELF_APPROVAL_BOTS` in the control, so adding a contributor is a
one-line change rather than a rewrite of this policy.

## What is deliberately *not* gated

**Translation quality.** Nothing here checks whether the Portuguese is good
Portuguese. That is not machine-checkable, and pretending otherwise would make
the policy dishonest about what it guarantees. What it guarantees is structural:
the file parses, the keys line up, the placeholders survive. A bad translation
merged under this policy is a bug to fix forward, not a gate to add.

## Enforcement

`.github/workflows/translation-self-approval.yml` runs on any PR touching
`packages/i18n/locales/**`. On `auto-approve` it submits a GitHub approving
review; on `needs-human` it comments with the failed gates and fails the job, so
the result can be required by a branch-protection rule.

**It approves. It never merges.** Clearing the gates means a human may merge the
PR without reading the diff — not that the machine should merge it unattended.

Three properties of that workflow are load-bearing:

- It checks out the **base** repo, never the PR head, so a PR cannot edit the
  policy, the scripts, or the workflow that judges it. `pull_request_target`
  hands a write-scoped token to code from a fork; checking out the PR would hand
  that token to the fork.
- It **executes nothing** from the PR. The collector reads blobs with
  `git show`, as data. No install, no build, no tests.
- It **fails closed**. A control that cannot run is reported as a failure, not
  folded into `needs-human` and certainly not into an approval.

A PR that changes `.github/workflows/` is not translation-only, so gate 1 routes
it to a human and it can never self-approve — this workflow included. The same
goes for a PR editing the policy or the scripts: the rules are never approved by
the rules, and that falls out of the scope gate rather than needing a list of
protected paths.

## Escalation

`needs-human` is advisory: a maintainer may still merge after reading the diff.
What the policy forbids is merging **unread** while a gate is red. When that
happens deliberately, say so in the merge — the exception should be visible in
the history, not silent.
