import { describe, expect, it } from "vitest";
import { getBookingsOutsideWorkingHours } from "./getBookingsOutsideWorkingHours";

// Mon-Fri, 09:00-17:00 wall clock.
const nineToFive = [
  {
    days: [1, 2, 3, 4, 5],
    startTime: new Date(Date.UTC(2023, 5, 12, 9, 0)),
    endTime: new Date(Date.UTC(2023, 5, 12, 17, 0)),
  },
];

const booking = (startISO: string, endISO: string, uid = "abc") => ({
  uid,
  title: "Intro call",
  startTime: new Date(startISO),
  endTime: new Date(endISO),
});

describe("getBookingsOutsideWorkingHours", () => {
  it("flags a booking that falls outside working hours in the trip timezone", () => {
    // 10:00 in Europe/Lisbon is 02:00 in America/Los_Angeles — outside 9-17 there.
    const result = getBookingsOutsideWorkingHours({
      bookings: [booking("2026-09-16T09:00:00.000Z", "2026-09-16T10:00:00.000Z")],
      availability: nineToFive,
      timeZone: "Europe/Lisbon",
      travelSchedule: {
        startDate: new Date("2026-09-14T00:00:00.000Z"),
        endDate: new Date("2026-09-20T00:00:00.000Z"),
        timeZone: "America/Los_Angeles",
      },
    });

    expect(result).toHaveLength(1);
    expect(result[0].uid).toBe("abc");
    expect(result[0].timeZone).toBe("America/Los_Angeles");
  });

  it("does not flag a booking that still sits inside working hours after the move", () => {
    // 17:00 UTC is 10:00 in Los Angeles — inside 9-17 there.
    const result = getBookingsOutsideWorkingHours({
      bookings: [booking("2026-09-16T17:00:00.000Z", "2026-09-16T18:00:00.000Z")],
      availability: nineToFive,
      timeZone: "Europe/Lisbon",
      travelSchedule: {
        startDate: new Date("2026-09-14T00:00:00.000Z"),
        endDate: new Date("2026-09-20T00:00:00.000Z"),
        timeZone: "America/Los_Angeles",
      },
    });

    expect(result).toEqual([]);
  });

  it("ignores bookings outside the trip window", () => {
    const result = getBookingsOutsideWorkingHours({
      bookings: [booking("2026-10-05T09:00:00.000Z", "2026-10-05T10:00:00.000Z")],
      availability: nineToFive,
      timeZone: "Europe/Lisbon",
      travelSchedule: {
        startDate: new Date("2026-09-14T00:00:00.000Z"),
        endDate: new Date("2026-09-20T00:00:00.000Z"),
        timeZone: "America/Los_Angeles",
      },
    });

    expect(result).toEqual([]);
  });

  it("covers every booking from the start date on when the trip has no end date", () => {
    const result = getBookingsOutsideWorkingHours({
      bookings: [booking("2026-12-01T09:00:00.000Z", "2026-12-01T10:00:00.000Z")],
      availability: nineToFive,
      timeZone: "Europe/Lisbon",
      travelSchedule: {
        startDate: new Date("2026-09-14T00:00:00.000Z"),
        endDate: null,
        timeZone: "America/Los_Angeles",
      },
    });

    expect(result).toHaveLength(1);
  });

  it("returns nothing when there are no bookings", () => {
    const result = getBookingsOutsideWorkingHours({
      bookings: [],
      availability: nineToFive,
      timeZone: "Europe/Lisbon",
      travelSchedule: {
        startDate: new Date("2026-09-14T00:00:00.000Z"),
        endDate: new Date("2026-09-20T00:00:00.000Z"),
        timeZone: "America/Los_Angeles",
      },
    });

    expect(result).toEqual([]);
  });

  it("flags a booking that only partially overlaps working hours", () => {
    // Ends at 17:30 Lisbon time, working day ends 17:00.
    const result = getBookingsOutsideWorkingHours({
      bookings: [booking("2026-09-16T15:30:00.000Z", "2026-09-16T16:30:00.000Z")],
      availability: nineToFive,
      timeZone: "Europe/Lisbon",
      travelSchedule: {
        startDate: new Date("2026-09-14T00:00:00.000Z"),
        endDate: new Date("2026-09-20T00:00:00.000Z"),
        timeZone: "Europe/Lisbon",
      },
    });

    expect(result).toHaveLength(1);
  });
  // Regression: the range window used to end exactly at the latest booking's
  // end instant. buildDateRanges clamps each day to that window, so the final
  // day's working hours collapsed onto the booking itself and it was always
  // reported outside them. Crossing the dateline hits this routinely, because
  // the booking lands on the day after the trip's last local day.
  describe("bookings near the edge of the range window", () => {
    // Every day 09:00-23:00, matching the seeded "Working Hours" schedule.
    const allWeekLateEvening = [
      {
        days: [0, 1, 2, 3, 4, 5, 6],
        startTime: new Date(Date.UTC(2023, 5, 12, 9, 0)),
        endTime: new Date(Date.UTC(2023, 5, 12, 23, 0)),
      },
    ];

    // 2026-09-11T01:00Z is 10:00 in Tokyo — inside 09:00-23:00 there.
    const acrossDateline = {
      bookings: [booking("2026-09-11T01:00:00.000Z", "2026-09-11T01:30:00.000Z")],
      availability: allWeekLateEvening,
      timeZone: "America/Fortaleza",
      travelSchedule: {
        startDate: new Date("2026-09-10T00:00:00.000Z"),
        endDate: new Date("2026-09-11T00:00:00.000Z"),
        timeZone: "Asia/Tokyo",
      },
    };

    it("does not flag a booking that is inside working hours in a timezone east of UTC", () => {
      expect(getBookingsOutsideWorkingHours(acrossDateline)).toEqual([]);
    });

    it("still flags the same booking when the destination puts it outside working hours", () => {
      // The same instant is 02:00 in London — outside 09:00-23:00.
      const result = getBookingsOutsideWorkingHours({
        ...acrossDateline,
        travelSchedule: { ...acrossDateline.travelSchedule, timeZone: "Europe/London" },
      });

      expect(result).toHaveLength(1);
    });

    it("does not flag a booking that ends exactly at the end of the working day", () => {
      // 22:00-23:00 in Lisbon, working day ends 23:00.
      const result = getBookingsOutsideWorkingHours({
        bookings: [booking("2026-09-16T21:00:00.000Z", "2026-09-16T22:00:00.000Z")],
        availability: allWeekLateEvening,
        timeZone: "Europe/Lisbon",
        travelSchedule: {
          startDate: new Date("2026-09-14T00:00:00.000Z"),
          endDate: new Date("2026-09-20T00:00:00.000Z"),
          timeZone: "Europe/Lisbon",
        },
      });

      expect(result).toEqual([]);
    });

    it("does not flag a booking that starts exactly at the start of the trip's first day", () => {
      // 09:00-10:00 in Lisbon on the trip's opening day.
      const result = getBookingsOutsideWorkingHours({
        bookings: [booking("2026-09-14T08:00:00.000Z", "2026-09-14T09:00:00.000Z")],
        availability: allWeekLateEvening,
        timeZone: "Europe/Lisbon",
        travelSchedule: {
          startDate: new Date("2026-09-14T00:00:00.000Z"),
          endDate: new Date("2026-09-20T00:00:00.000Z"),
          timeZone: "Europe/Lisbon",
        },
      });

      expect(result).toEqual([]);
    });

    it("evaluates each booking independently when several share a trip", () => {
      const result = getBookingsOutsideWorkingHours({
        bookings: [
          // 10:00 Tokyo - inside hours.
          booking("2026-09-11T01:00:00.000Z", "2026-09-11T01:30:00.000Z", "inside"),
          // 03:00 Tokyo - outside hours.
          booking("2026-09-10T18:00:00.000Z", "2026-09-10T18:30:00.000Z", "outside"),
        ],
        availability: allWeekLateEvening,
        timeZone: "America/Fortaleza",
        travelSchedule: {
          startDate: new Date("2026-09-10T00:00:00.000Z"),
          endDate: new Date("2026-09-11T00:00:00.000Z"),
          timeZone: "Asia/Tokyo",
        },
      });

      expect(result.map((entry) => entry.uid)).toEqual(["outside"]);
    });
  });
});
