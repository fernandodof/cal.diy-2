import { describe, it, expect } from "vitest";

import convertToNewDurationType from "./convertToNewDurationType";

describe("convertToNewDurationType", () => {
  it("should return the value unchanged when the type does not change", () => {
    expect(convertToNewDurationType("minutes", "minutes", 90)).toBe(90);
    expect(convertToNewDurationType("hours", "hours", 5)).toBe(5);
    expect(convertToNewDurationType("days", "days", 3)).toBe(3);
  });

  it("should convert minutes to hours and days", () => {
    expect(convertToNewDurationType("minutes", "hours", 120)).toBe(2);
    expect(convertToNewDurationType("minutes", "days", 2880)).toBe(2);
  });

  it("should convert hours to minutes and days", () => {
    expect(convertToNewDurationType("hours", "minutes", 2)).toBe(120);
    expect(convertToNewDurationType("hours", "days", 48)).toBe(2);
  });

  it("should convert days to minutes and hours", () => {
    expect(convertToNewDurationType("days", "minutes", 2)).toBe(2880);
    expect(convertToNewDurationType("days", "hours", 2)).toBe(48);
  });

  it("should round up conversions that do not divide evenly", () => {
    expect(convertToNewDurationType("minutes", "hours", 90)).toBe(2);
    expect(convertToNewDurationType("minutes", "days", 1441)).toBe(2);
    expect(convertToNewDurationType("hours", "days", 25)).toBe(2);
  });

  it("should handle zero for every conversion", () => {
    expect(convertToNewDurationType("minutes", "minutes", 0)).toBe(0);
    expect(convertToNewDurationType("minutes", "hours", 0)).toBe(0);
    expect(convertToNewDurationType("minutes", "days", 0)).toBe(0);
    expect(convertToNewDurationType("hours", "minutes", 0)).toBe(0);
    expect(convertToNewDurationType("hours", "hours", 0)).toBe(0);
    expect(convertToNewDurationType("hours", "days", 0)).toBe(0);
    expect(convertToNewDurationType("days", "minutes", 0)).toBe(0);
    expect(convertToNewDurationType("days", "hours", 0)).toBe(0);
    expect(convertToNewDurationType("days", "days", 0)).toBe(0);
  });
});
