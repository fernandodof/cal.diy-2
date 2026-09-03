# CLAUDE.md

Notes for agents working in this repo. This is a Cal.com fork; most conventions
come from upstream. Sections below record decisions specific to this fork that
are **not** derivable from the code.

## Working hours & timezones

Decided in a `/grill-me` interview on 2026-09-01. Scope: per-user working hours
(each user sets their own availability in their own timezone). These are product
intent, recorded because the schema alone cannot express them.

### The ambiguity

`Availability.startTime`/`endTime` are `@db.Time` — wall-clock, no date, no
offset. The timezone lives on `Schedule.timeZone`, which is **nullable** and
falls back to the user's current profile timezone. So identical DB rows resolve
to different UTC windows as a user's timezone changes.

`Booking.startTime` is a plain `DateTime` (a fixed UTC instant, no timezone
column). Availability is therefore *relative* while bookings are *absolute*, and
the two drift apart whenever a user's offset changes.

### Decisions

1. **Availability follows the person.** Stored hours mean "when I am awake,
   wherever I am" — not a commitment pinned to the timezone they were set in.
   Move to a new timezone and 9–17 becomes 9–17 *there*.
   → The nullable `Schedule.timeZone` is **intentional**, not a latent bug. Do
   not "fix" it with a backfill + non-null migration.

2. **Confirmed bookings never move.** No auto-cancel, no auto-reschedule, and
   the attendee is not notified when a host's offset change leaves a booking
   outside their new working hours. The instant was agreed; it stands.

3. **Warn the host on travel, stay silent on DST.** Both produce the identical
   symptom (offset changed, existing bookings now sit outside working hours),
   so the distinguishing rule is **agency**: travel is a change the user *made*,
   DST is a change made *to* them. Travel carries a decision worth surfacing;
   DST twice a year for every user is noise.

4. **Warn at trip-scheduling time, not at cron-switchover.** `TravelSchedule`
   is applied unattended by an hourly cron (`.github/workflows/cron-changeTimeZone.yml`),
   so a warning at switchover fires mid-trip with nobody watching. Surface it
   when the user picks the trip dates — the only moment the warning reaches
   someone who can still act. Costs a lookahead query over future bookings.

5. **COLLECTIVE events: warn hosts, give attendees a fallback.** A host moving
   can collapse the intersection of everyone's hours to zero, leaving a live
   booking page with no bookable slot. Warn the hosts early (same rule as #4),
   and show attendees a request-a-time fallback rather than an unexplained empty
   calendar, so the lead is not silently lost.

### Applying these

- A user-visible "outside working hours" state is **advisory**. Nothing in this
  area should ever mutate or cancel a `Booking` on the user's behalf.
- Warnings are **host-facing and early**. The attendee-facing surface is the
  request-a-time fallback in #5 — not out-of-hours notifications.
