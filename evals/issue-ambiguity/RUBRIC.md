# Issue ambiguity rubric (0–3)

One question: **can a competent contributor who does not know this codebase start work from
the issue alone, without asking the creator a question first?**

Score the issue as written, not how difficult it is to implement.

| Score | Label | Meaning |
|-------|-------|---------|
| **0** | Unactionable | No end state is stated at all. There is nothing to build toward. |
| **1** | Highly ambiguous | The area is clear but the key decision is not. A contributor would have to guess, and a wrong guess wastes the work. |
| **2** | Mostly clear | Expected behaviour and scope are clear. Secondary details are open but can be resolved in review. |
| **3** | Unambiguous | Behaviour, scope, and acceptance are pinned down. A contributor could open a PR without asking a question. |

## What to look at

- **Expected behaviour** — is the intended end state stated, not just the complaint?
- **Reproduction** — can the reader trigger or observe the problem?
- **Scope** — is it clear what is and is not included?
- **Acceptance** — would two contributors agree on whether a given PR closes this?

## Boundaries

- **0 vs 1** — 0 is only for a missing end state ("make it nicer", "improve performance").
  An issue naming a concrete malfunction is at least a 1, however thin the detail.
- **2 vs 3** — open scope caps a score at 2 only when the gap would change *what gets built*.
  A gap that review would settle anyway does not hold back a 3.
- **3 without pointers** — naming the fix or the file is a bonus, not a requirement. Behaviour
  plus reproduction is enough for a 3.
