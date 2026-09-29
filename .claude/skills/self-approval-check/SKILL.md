---
name: self-approval-check
description: Decide whether a translation pull request can be merged without a human reading the diff. Gathers the evidence, runs the self-approval control, and reports the verdict with the gates that failed. Use when asked to check, approve, or merge a translation PR, or to triage the locale PRs waiting in the queue.
---

# Self-approval check

One question: **may this translation PR be merged without a human reading the
diff?** The answer is `auto-approve` or `needs-human`, and it comes from
`scripts/pr-self-approval.sh`, which implements
[docs/harness/pr-self-approval-policy.md](../../../docs/harness/pr-self-approval-policy.md).

**You do not decide the verdict** — the script does. Your job is to run it and
report what it found. If you disagree with its answer, say so in your report and
leave the verdict standing.

## Run it

Two scripts: one gathers evidence, one judges it.

```bash
./scripts/pr-evidence.sh <pr-number> | ./scripts/pr-self-approval.sh --json
```

`pr-self-approval.sh <pr-number>` collects the evidence itself and is fine for a
one-off. Split the pipeline when you want the evidence for something else —
keeping it to re-judge after a policy change, or judging a PR whose evidence was
gathered elsewhere:

```bash
./scripts/pr-evidence.sh 123 > /tmp/ev.json
./scripts/pr-self-approval.sh --json --evidence /tmp/ev.json
```

Exit code `0` is `auto-approve`, `1` is `needs-human`, `2` means the run itself
failed (a missing `gh` login, unreadable evidence, an unsupported schema). Exit
`2` is **not** an approval — it means the check did not run, and the PR needs a
human by default.

Evidence the collector could not reach comes back as `null`, and the policy
turns that into a failed gate with an `evidence:` reason. It never passes on
facts it does not have.

## Report

Lead with the verdict and the PR, then the reasons. Keep it short — this gets
read in a queue.

```
PR #123 — needs-human
  pt-BR: 2 key(s) have mismatched {{placeholders}}
  CI: not green (check-types=FAILURE)
```

For `auto-approve`, say what was checked, not just that it passed:

```
PR #123 — auto-approve
  41 locale files, no key drift, placeholders intact, CI green
```

When the verdict is `needs-human`, **name what a human should look at**. A
placeholder mismatch means opening those specific keys; a CI failure means
reading that job's log. A reason without a next step wastes the reader's time.

## Triaging a queue

Asked to check everything open, list the PRs and run the pair on each:

```bash
gh pr list --state open --json number,title,author --limit 50
```

Report as a table — verdict, PR, one-line reason — and put the `auto-approve`
rows last. The ones needing attention go at the top.

## Rules

- **Never merge on your own.** This skill produces a verdict, not a merge. Even
  `auto-approve` means "a human may merge this unread", not "merge it". Merging
  is a separate, explicit instruction.
- **Never re-run the control to get a better answer.** If it says
  `needs-human`, that is the answer. Changing the PR to pass a gate is fine;
  re-running until the flake clears is not.
- **Report failures honestly.** An exit `2` is reported as "the check could not
  run", never as a pass. A gate you skipped is a gate that failed.
- **The policy is not yours to edit.** A change to the rules is never approved
  by the rules. If a gate is wrong, say so in your report and let a maintainer
  change it.
