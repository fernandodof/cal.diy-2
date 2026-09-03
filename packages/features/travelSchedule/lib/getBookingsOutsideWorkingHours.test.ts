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
});
