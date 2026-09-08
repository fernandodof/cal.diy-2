# Commits and pull requests

## Commit format

Conventional commits, scoped to the feature area, one per tracer bullet:

```
feat(travel-schedule): warn host about bookings outside working hours
fix(emails): customReplyToEmail no longer dropped when hideOrganizerEmail is true
```

Every commit message ends with the attribution trailers the session is
configured with — check the current session's attribution instructions rather
than copying a fixed block from here, since they change per session.

## PR body template

```markdown
## What changed

<One paragraph: the behavior that is different now, from the user's point of view.>

## Tracer bullets

1. <Slice title> — <what it proves end-to-end>
2. <Slice title> — <what it proves end-to-end>

## How to verify

<Numbered steps a reviewer can actually follow in the running app or the tests.>

Checks run on this branch:

- `yarn test packages/features/<area>/<file>.test.ts` — <result>
- `yarn turbo run type-check --filter=@calcom/<package>` — <result>
```

Report check results honestly. If something was skipped or is failing, say which
and why — a PR body that claims green on red is worse than no PR body.

When the change respects a decision recorded in `CLAUDE.md`, cite it in
**What changed** so the reviewer sees the constraint the design is honoring.

## Creating the PR

The base branch is **asked, never assumed** — `origin` here is a personal fork of
cal.com, so both the fork's `main` and upstream are plausible targets and picking
wrong sends the change to the wrong place.

```bash
git push -u origin <branch>
gh pr create --base <the branch the user named> --title "<conventional commit title>" --body "$(cat <<'BODY'
...body from the template...
BODY
)"
```

PR descriptions end with the generation footer from the session's attribution
instructions.

Return the PR URL to the user as the final output.
