import { describe, expect, it } from "vitest";
import { getBusinessHoursRange, isOutsideBusinessHours } from "./businessHours";

describe("isOutsideBusinessHours", () => {
  // 2024-01-08 is a Monday.
  it("returns false during a weekday business day", () => {
    expect(isOutsideBusinessHours("2024-01-08T12:00:00Z", "UTC")).toBe(false);
  });

  it("treats the start of the window as inside and the end as outside", () => {
    expect(isOutsideBusinessHours("2024-01-08T09:00:00Z", "UTC")).toBe(false);
    expect(isOutsideBusinessHours("2024-01-08T17:59:00Z", "UTC")).toBe(false);
    expect(isOutsideBusinessHours("2024-01-08T18:00:00Z", "UTC")).toBe(true);
    expect(isOutsideBusinessHours("2024-01-08T08:59:00Z", "UTC")).toBe(true);
  });

  it("returns true on weekends", () => {
    expect(isOutsideBusinessHours("2024-01-06T12:00:00Z", "UTC")).toBe(true); // Saturday
    expect(isOutsideBusinessHours("2024-01-07T12:00:00Z", "UTC")).toBe(true); // Sunday
  });

  it("evaluates the instant in the given timezone", () => {
    // Monday 12:00 UTC is Monday 04:00 in Los Angeles — outside there, inside in UTC.
    expect(isOutsideBusinessHours("2024-01-08T12:00:00Z", "UTC")).toBe(false);
    expect(isOutsideBusinessHours("2024-01-08T12:00:00Z", "America/Los_Angeles")).toBe(true);

    // Monday 23:00 UTC is already Tuesday 08:00 in Tokyo — outside in both, but for different reasons.
    expect(isOutsideBusinessHours("2024-01-08T23:00:00Z", "Asia/Tokyo")).toBe(true);
    expect(isOutsideBusinessHours("2024-01-09T01:00:00Z", "Asia/Tokyo")).toBe(false);
  });

  it("returns false for an invalid date", () => {
    expect(isOutsideBusinessHours("not-a-date", "UTC")).toBe(false);
    expect(isOutsideBusinessHours(null)).toBe(false);
  });

  it("does not throw on an unknown timezone", () => {
    // Falls back to the runner's local offset, so only the absence of a throw is asserted.
    expect(() => isOutsideBusinessHours("2024-01-08T12:00:00Z", "Not/AZone")).not.toThrow();
  });
});

describe("getBusinessHoursRange", () => {
  it("formats in 24h by default", () => {
    expect(getBusinessHoursRange()).toEqual({ start: "09:00", end: "18:00" });
  });

  it("formats in 12h when requested", () => {
    expect(getBusinessHoursRange(12)).toEqual({ start: "9:00am", end: "6:00pm" });
  });
});
