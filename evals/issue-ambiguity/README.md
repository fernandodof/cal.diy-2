# Issue ambiguity scorer

Scores a GitHub issue 0–3 on how ambiguous it is, with an LLM judge, and compares
the judge against human scores.

## Layout

| Path | What it is |
|------|------------|
| `RUBRIC.md` | The 0–3 scale. Inlined into the judge prompt, so edits change scoring. |
| `snapshot.sh` | Freezes a GitHub issue into `cases/`. |
| `score.sh` | Scores one case file, or a live issue with `--issue`. |
| `run.sh` | Scores the whole set and prints the comparison. |
| `cases/` | Frozen issue snapshots with a human score in the frontmatter. |
| `runs/` | Timestamped run output. |

## Usage

```sh
./snapshot.sh 19                     # freeze an issue from this repo
./snapshot.sh calcom/cal.com#30121   # ...or any other repo
./run.sh                             # score the set, compare to human scores
./score.sh --issue 21                # score a live issue, store nothing
```

`JUDGE_MODEL` overrides the judge (default `claude-haiku-4-5-20251001`).
`EVAL_REPO` overrides the default repo for bare issue numbers.

## Two paths, on purpose

**The eval set is frozen.** `cases/` holds issue text as it was on the snapshot date.
A re-score only means something if the input held still: when a score moves, you need
to know whether the rubric changed or the issue did. Re-snapshotting an issue whose
body changed writes a new version (`issue-19.v2.md`) beside the original rather than
overwriting it, so the score delta between versions shows what the author's update
bought.

**Live scoring fetches.** `score.sh --issue N` scores current text and stores nothing.
This is the path for triaging a real issue, where the score *should* move as the author
adds detail.

A case with a blank `human_score` is skipped by `run.sh` — there is nothing to compare
it against.

## Reading a run

`exact` is strict agreement, `within_1` counts adjacent scores, and `mean_abs_error`
is the average distance. Disagreements are the useful output: each case carries the
judge's one-line reasoning, and a cluster of misses in the same direction usually
points at an underdetermined part of the rubric rather than a bad judge.
