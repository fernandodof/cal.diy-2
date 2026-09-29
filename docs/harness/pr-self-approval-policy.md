# PR self-approval policy — translation changes

Many pull requests in this fork are written by an agent or by the lingo.dev bot
(`.github/workflows/i18n.yml`), and translation PRs are the highest-volume,
lowest-signal thing in the queue: a change across 44 locales in
`packages/i18n/locales/<lang>/common.json` is thousands of lines nobody will
read line by line. Reviewer attention is the scarce resource, and spending it
here is how it gets wasted.

So translations are where self-approval pays. This policy defines exactly when a
**translation-only** PR may be merged without a human reading the diff.

`scripts/pr-self-approval.sh` implements it; the `self-approval-check` skill
collects the evidence and runs it.

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

## Escalation

`needs-human` is advisory: a maintainer may still merge after reading the diff.
What the policy forbids is merging **unread** while a gate is red. When that
happens deliberately, say so in the merge — the exception should be visible in
the history, not silent.
