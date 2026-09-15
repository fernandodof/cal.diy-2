import { describe, expect, it } from "vitest";

import { isTimeSlotOutsideWorkingHours } from "./isTimeslotOutsideWorkingHours";

describe("isTimeSlotOutsideWorkingHours", () => {
  it("should return true when the selected slot is flagged", () => {
    const slotToCheckInIso = "2026-09-19T20:00:00.000Z";

    const result = isTimeSlotOutsideWorkingHours({
      scheduleData: {
        slots: {
          "2026-09-19": [{ time: slotToCheckInIso, isOutsideWorkingHours: true }],
        },
      },
      slotToCheckInIso,
    });

    expect(result).toBe(true);
  });

  it("should return false when the selected slot is not flagged", () => {
    const slotToCheckInIso = "2026-09-14T10:00:00.000Z";

    const result = isTimeSlotOutsideWorkingHours({
      scheduleData: {
        slots: {
          "2026-09-14": [{ time: slotToCheckInIso }],
        },
      },
      slotToCheckInIso,
    });

    expect(result).toBe(false);
  });

  it("should find the slot when the booker's timezone files it under the next date", () => {
    // The slot's ISO date is the 19th, but the booker's timezone keys it under the 20th.
    const slotToCheckInIso = "2026-09-19T20:00:00.000Z";

    const result = isTimeSlotOutsideWorkingHours({
      scheduleData: {
        slots: {
          "2026-09-20": [{ time: slotToCheckInIso, isOutsideWorkingHours: true }],
        },
      },
      slotToCheckInIso,
    });

    expect(result).toBe(true);
  });

  it("should return false when scheduleData is null", () => {
    const result = isTimeSlotOutsideWorkingHours({
      scheduleData: null,
      slotToCheckInIso: "2026-09-19T20:00:00.000Z",
    });

    expect(result).toBe(false);
  });

  it("should return false when the slot is not in the schedule data", () => {
    const result = isTimeSlotOutsideWorkingHours({
      scheduleData: {
        slots: {
          "2026-09-19": [{ time: "2026-09-19T21:00:00.000Z", isOutsideWorkingHours: true }],
        },
      },
      slotToCheckInIso: "2026-09-19T20:00:00.000Z",
    });

    expect(result).toBe(false);
  });

  it("should return false when the slot is not a valid ISO string", () => {
    const result = isTimeSlotOutsideWorkingHours({
      scheduleData: {
        slots: {
          "2026-09-19": [{ time: "2026-09-19T20:00:00.000Z", isOutsideWorkingHours: true }],
        },
      },
      slotToCheckInIso: "",
    });

    expect(result).toBe(false);
  });
});
