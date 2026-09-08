# Grounding checklist — where code lives in this fork

Cal.com is a large yarn/turbo monorepo. Work down this list until you can name
the concrete files the task touches. Stop as soon as you have them.

## 1. Follow the user-visible surface inward

Start from what the user sees and walk toward the data.

| Layer | Where to look |
|---|---|
| Pages / routes | `apps/web/app/`, `apps/web/modules/` |
| Feature UI + logic | `packages/features/<area>/` |
| Shared components | `packages/ui/`, `packages/features/components/` |
| API handlers | `packages/trpc/server/routers/viewer/<area>/` |
| Business logic | `packages/lib/`, `packages/features/<area>/lib/` |
| Schema | `packages/prisma/schema.prisma` |

`packages/features/` and the tRPC router directories share the same area names
(`availability`, `bookings`, `eventtypes`, `calendars`, …). Finding the area in
one tells you where to look in the other.

## 2. Grep for the domain noun

Search the term the user used, not the term you'd pick:

```bash
grep -rn "TravelSchedule" packages/ apps/web/ --include=*.ts --include=*.tsx -l | head -20
```

Prisma model names are the highest-signal search terms — they appear in the
schema, the queries, the tRPC handlers, and the types.

## 3. Find the nearest test

```bash
find packages/features/<area> -name "*.test.ts" | head
```

Read one before writing any. It shows how this area builds fixtures, mocks
Prisma, and handles timezones. Tests here run under `TZ=UTC` — anything
timezone-sensitive must set its zone explicitly rather than rely on the ambient one.

## 4. Check the fork's recorded decisions

`CLAUDE.md` at the repo root records product intent the code cannot express —
currently the working-hours and timezone rules. If the area you're touching
appears there, the decisions are binding constraints on your design, not
suggestions. Cite the relevant one in your slice plan so the user can see you
read it.

## Timezone gotchas in this repo

Worth knowing before touching anything schedule-related:

- `Availability.startTime` / `endTime` are `@db.Time` — wall-clock, no offset.
- `Schedule.timeZone` is **nullable by design**; it falls back to the user's
  profile timezone. Do not "fix" this.
- `Booking.startTime` is an absolute UTC instant with no timezone column.

Availability is relative; bookings are absolute. Most bugs in this area come
from treating one as the other.
