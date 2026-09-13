# CLAUDE.md

A personal fork of [Cal.com](https://github.com/calcom/cal.com), used as a sandbox
for experimenting with features and with agent workflows. It tracks upstream
closely, so **upstream Cal.com conventions beat personal preference** — match the
naming, comment density, and idioms of the code around your change.

Yarn 4 + turbo monorepo; scripts live in `package.json`. Two that read as
something they are not: `yarn lint` and `yarn format` run **biome**, and
`yarn test` pins `TZ=UTC`, so anything timezone-sensitive must set its zone
explicitly rather than lean on the ambient one.

`packages/features/` and `packages/trpc/server/routers/viewer/` share area names
but not spellings — `eventtypes` in features is `eventTypes` in tRPC. Confirm
with `ls` rather than assuming.

For anything larger than a small fix, run `/implement-task` — it carries the
codebase map, the verification commands, and the spec-folder workflow.
