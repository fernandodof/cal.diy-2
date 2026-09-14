import { describe, expect, it } from "vitest";

import dayjs from "@calcom/dayjs";

import { getRecurringAvailability, isOutsideRecurringHours } from "./isOutsideRecurringHours";

// Availability stores time-of-day as a UTC wall clock, read back with
// getUTCHours()/getUTCMinutes(). Build fixtures the same way.
const time = (hours: number, minutes = 0) => new Date(Date.UTC(1970, 0, 1, hours, minutes));

const weekdays9to5 = {
  days: [1, 2, 3, 4, 5],
  startTime: time(9),
  endTime: time(17),
  date: null,
};

const saturdayOverride = {
  days: [],
  startTime: time(20),
  endTime: time(22),
  date: new Date(Date.UTC(2026, 8, 19)),
};

describe("getRecurringAvailability", () => {
  it("keeps recurring weekly rows", () => {
    expect(getRecurringAvailability([weekdays9to5])).toEqual([weekdays9to5]);
  });

  it("drops date overrides", () => {
    expect(getRecurringAvailability([saturdayOverride])).toEqual([]);
  });

  it("drops rows with no days, even without a date", () => {
    expect(getRecurringAvailability([{ ...saturdayOverride, date: null }])).toEqual([]);
  });
});

describe("isOutsideRecurringHours", () => {
  const timeZone = "UTC";

  it("is false for a booking inside the recurring hours", () => {
    // Monday 2026-09-14, 10:00-11:00 UTC
    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-14T10:00:00Z"),
        end: dayjs.utc("2026-09-14T11:00:00Z"),
        availability: [weekdays9to5],
        timeZone,
      })
    ).toBe(false);
  });

  it("is true for a booking a date override opened outside the recurring hours", () => {
    // Saturday 2026-09-19, 20:00-21:00 UTC — bookable only via the override
    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-19T20:00:00Z"),
        end: dayjs.utc("2026-09-19T21:00:00Z"),
        availability: [weekdays9to5, saturdayOverride],
        timeZone,
      })
    ).toBe(true);
  });

  it("is true for a booking that starts inside but ends outside the recurring hours", () => {
    // Monday 16:30-17:30 — not fully contained, mirroring hasDateRangeForBooking
    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-14T16:30:00Z"),
        end: dayjs.utc("2026-09-14T17:30:00Z"),
        availability: [weekdays9to5],
        timeZone,
      })
    ).toBe(true);
  });

  it("is false when the booking exactly fills the recurring window", () => {
    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-14T09:00:00Z"),
        end: dayjs.utc("2026-09-14T17:00:00Z"),
        availability: [weekdays9to5],
        timeZone,
      })
    ).toBe(false);
  });

  it("is false when the host has no recurring rows at all", () => {
    // No baseline to judge against — flag nothing rather than flag everything.
    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-19T20:00:00Z"),
        end: dayjs.utc("2026-09-19T21:00:00Z"),
        availability: [saturdayOverride],
        timeZone,
      })
    ).toBe(false);
  });

  it("judges the booking in the schedule's timezone, not the ambient one", () => {
    // yarn test pins TZ=UTC, so the zone has to be explicit to mean anything.
    // 9-17 in New York is 13:00-21:00 UTC. A 14:00 UTC booking is inside;
    // the same wall-clock time judged in UTC would be outside.
    const newYork = "America/New_York";

    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-14T14:00:00Z"),
        end: dayjs.utc("2026-09-14T15:00:00Z"),
        availability: [weekdays9to5],
        timeZone: newYork,
      })
    ).toBe(false);

    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-14T09:30:00Z"),
        end: dayjs.utc("2026-09-14T10:00:00Z"),
        availability: [weekdays9to5],
        timeZone: newYork,
      })
    ).toBe(true);
  });

  it("treats an 11:59PM end as running to midnight", () => {
    // Mirrors the allowance in processWorkingHours.
    const lateShift = { days: [1], startTime: time(18), endTime: time(23, 59), date: null };

    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-14T23:30:00Z"),
        end: dayjs.utc("2026-09-15T00:00:00Z"),
        availability: [lateShift],
        timeZone,
      })
    ).toBe(false);
  });

  it("uses the weekday of the booking in the schedule's timezone", () => {
    // 2026-09-14T02:00Z is Monday in UTC but still Sunday in New York,
    // where there is no recurring availability.
    expect(
      isOutsideRecurringHours({
        start: dayjs.utc("2026-09-14T02:00:00Z"),
        end: dayjs.utc("2026-09-14T03:00:00Z"),
        availability: [weekdays9to5],
        timeZone: "America/New_York",
      })
    ).toBe(true);
  });
});
