import prismock from "@calcom/testing/lib/__mocks__/prisma";
import { BookingStatus } from "@calcom/prisma/enums";
import { beforeEach, describe, expect, it } from "vitest";

import { TravelScheduleRepository } from "./TravelScheduleRepository";

const userId = 1;
const scheduleId = 10;

/** 2026-09-09 01:00 UTC — 22:00 in America/Fortaleza (UTC-3). */
const BOOKING_START = new Date("2026-09-09T01:00:00.000Z");
const BOOKING_END = new Date("2026-09-09T01:30:00.000Z");

const seed = async () => {
  await prismock.user.create({
    data: {
      id: userId,
      email: "pro@example.com",
      timeZone: "America/Fortaleza",
      defaultScheduleId: scheduleId,
    },
  });

  await prismock.schedule.create({
    data: {
      id: scheduleId,
      userId,
      name: "Working Hours",
      timeZone: "America/Fortaleza",
    },
  });

  await prismock.availability.create({
    data: {
      scheduleId,
      days: [0, 1, 2, 3, 4, 5, 6],
      startTime: new Date(Date.UTC(1970, 0, 1, 9, 0)),
      endTime: new Date(Date.UTC(1970, 0, 1, 23, 0)),
    },
  });

  await prismock.booking.create({
    data: {
      uid: "booking-during-trip",
      title: "30min",
      userId,
      status: BookingStatus.ACCEPTED,
      startTime: BOOKING_START,
      endTime: BOOKING_END,
    },
  });
};

describe("TravelScheduleRepository.findWorkingHoursLookaheadData", () => {
  beforeEach(async () => {
    await seed();
  });

  // Regression: the modal opens with startDate and endDate both defaulting to
  // `new Date()`. Passing those through to the SQL filter unnormalized made the
  // window zero-width, so no booking was ever returned and the warning could
  // never render. The dates must be widened to day boundaries.
  it("returns bookings on the trip's start day when start and end are the same instant", async () => {
    const sameInstant = new Date("2026-09-09T14:23:45.000Z");

    const result = await TravelScheduleRepository.findWorkingHoursLookaheadData({
      userId,
      dateFrom: sameInstant,
      dateTo: sameInstant,
    });

    expect(result?.bookings.map((booking) => booking.uid)).toEqual(["booking-during-trip"]);
  });

  it("includes a booking earlier in the day than the trip's start instant", async () => {
    // Mid-afternoon on the booking's day: a raw `gte` would exclude the 01:00 booking.
    const afternoon = new Date("2026-09-09T18:00:00.000Z");

    const result = await TravelScheduleRepository.findWorkingHoursLookaheadData({
      userId,
      dateFrom: afternoon,
      dateTo: afternoon,
    });

    expect(result?.bookings.map((booking) => booking.uid)).toEqual(["booking-during-trip"]);
  });

  it("includes a booking later in the day than the trip's end instant", async () => {
    // A raw `lte` at midnight would exclude the 01:00 booking on the end day.
    const result = await TravelScheduleRepository.findWorkingHoursLookaheadData({
      userId,
      dateFrom: new Date("2026-09-08T00:00:00.000Z"),
      dateTo: new Date("2026-09-09T00:00:00.000Z"),
    });

    expect(result?.bookings.map((booking) => booking.uid)).toEqual(["booking-during-trip"]);
  });

  it("returns the booking for an open-ended trip", async () => {
    const result = await TravelScheduleRepository.findWorkingHoursLookaheadData({
      userId,
      dateFrom: new Date("2026-09-09T14:00:00.000Z"),
      dateTo: undefined,
    });

    expect(result?.bookings.map((booking) => booking.uid)).toEqual(["booking-during-trip"]);
  });

  it("excludes bookings that fall outside the trip window", async () => {
    const result = await TravelScheduleRepository.findWorkingHoursLookaheadData({
      userId,
      dateFrom: new Date("2026-10-01T00:00:00.000Z"),
      dateTo: new Date("2026-10-05T00:00:00.000Z"),
    });

    expect(result?.bookings).toEqual([]);
  });

  it("excludes bookings that are not confirmed", async () => {
    await prismock.booking.create({
      data: {
        uid: "pending-booking",
        title: "Tennis class",
        userId,
        status: BookingStatus.PENDING,
        startTime: new Date("2026-09-09T02:00:00.000Z"),
        endTime: new Date("2026-09-09T03:00:00.000Z"),
      },
    });

    const result = await TravelScheduleRepository.findWorkingHoursLookaheadData({
      userId,
      dateFrom: new Date("2026-09-09T14:00:00.000Z"),
      dateTo: new Date("2026-09-09T14:00:00.000Z"),
    });

    expect(result?.bookings.map((booking) => booking.uid)).toEqual(["booking-during-trip"]);
  });

  it("resolves the availability and timezone from the user's default schedule", async () => {
    const result = await TravelScheduleRepository.findWorkingHoursLookaheadData({
      userId,
      dateFrom: new Date("2026-09-09T14:00:00.000Z"),
      dateTo: new Date("2026-09-09T14:00:00.000Z"),
    });

    expect(result?.timeZone).toBe("America/Fortaleza");
    expect(result?.availability).toHaveLength(1);
    expect(result?.availability[0]).toMatchObject({ days: [0, 1, 2, 3, 4, 5, 6] });
  });

  it("returns null when the user does not exist", async () => {
    const result = await TravelScheduleRepository.findWorkingHoursLookaheadData({
      userId: 999,
      dateFrom: new Date("2026-09-09T00:00:00.000Z"),
      dateTo: new Date("2026-09-09T00:00:00.000Z"),
    });

    expect(result).toBeNull();
  });
});
