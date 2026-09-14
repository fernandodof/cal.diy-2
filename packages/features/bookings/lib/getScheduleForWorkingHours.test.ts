import { describe, expect, it } from "vitest";

import { getScheduleForWorkingHours } from "./getScheduleForWorkingHours";

const time = (hours: number): Date => new Date(Date.UTC(1970, 0, 1, hours));

const weekdayAvailability = [
  { days: [1, 2, 3, 4, 5], startTime: time(9), endTime: time(17), date: null },
];

const user = {
  id: 1,
  timeZone: "America/New_York",
  defaultScheduleId: 100,
  schedules: [{ id: 100, timeZone: "Europe/London", availability: weekdayAvailability }],
};

describe("getScheduleForWorkingHours", () => {
  it("falls back to the user's default schedule when the event type has none", () => {
    // The common case: event types usually inherit the user's default schedule rather
    // than setting their own, so reading eventType.schedule alone finds nothing.
    const result = getScheduleForWorkingHours({
      eventType: { hosts: [], timeZone: null, schedule: null },
      user,
    });

    expect(result).toEqual({ availability: weekdayAvailability, timeZone: "Europe/London" });
  });

  it("prefers the event type's own schedule", () => {
    const eventTypeAvailability = [
      { days: [6], startTime: time(10), endTime: time(12), date: null },
    ];

    const result = getScheduleForWorkingHours({
      eventType: {
        hosts: [],
        timeZone: null,
        schedule: { id: 999, timeZone: "Asia/Tokyo", availability: eventTypeAvailability },
      },
      user,
    });

    expect(result).toEqual({ availability: eventTypeAvailability, timeZone: "Asia/Tokyo" });
  });

  it("prefers the host's schedule over the user's default", () => {
    const hostAvailability = [{ days: [2], startTime: time(8), endTime: time(10), date: null }];

    const result = getScheduleForWorkingHours({
      eventType: {
        hosts: [
          { user: { id: 1 }, schedule: { id: 555, timeZone: "Asia/Tokyo", availability: hostAvailability } },
        ],
        timeZone: null,
        schedule: null,
      },
      user,
    });

    expect(result).toEqual({ availability: hostAvailability, timeZone: "Asia/Tokyo" });
  });

  it("returns null when there is no real schedule anywhere", () => {
    // detectEventTypeScheduleForUser would substitute a synthetic Mon-Fri 9-5 here.
    // Judging against hours the host never set would flag their own availability.
    const result = getScheduleForWorkingHours({
      eventType: { hosts: [], timeZone: null, schedule: null },
      user: { ...user, defaultScheduleId: null, schedules: [] },
    });

    expect(result).toBeNull();
  });

  it("returns null when the schedule has no availability rows", () => {
    const result = getScheduleForWorkingHours({
      eventType: { hosts: [], timeZone: null, schedule: null },
      user: { ...user, schedules: [{ id: 100, timeZone: "Europe/London", availability: [] }] },
    });

    expect(result).toBeNull();
  });
});
