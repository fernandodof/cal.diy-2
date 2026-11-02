import { describe, expect, it } from "vitest";
import convertToNewDurationType from "./convertToNewDurationType";

describe("convertToNewDurationType", () => {
  it("should return the value unchanged for identity conversions", () => {
    expect(convertToNewDurationType("minutes", "minutes", 45)).toBe(45);
    expect(convertToNewDurationType("hours", "hours", 5)).toBe(5);
    expect(convertToNewDurationType("days", "days", 3)).toBe(3);
  });

  it("should convert minutes to hours", () => {
    expect(convertToNewDurationType("minutes", "hours", 120)).toBe(2);
  });

  it("should convert minutes to days", () => {
    expect(convertToNewDurationType("minutes", "days", 2880)).toBe(2);
  });

  it("should convert hours to minutes", () => {
    expect(convertToNewDurationType("hours", "minutes", 2)).toBe(120);
  });

  it("should convert hours to days", () => {
    expect(convertToNewDurationType("hours", "days", 48)).toBe(2);
  });

  it("should convert days to minutes", () => {
    expect(convertToNewDurationType("days", "minutes", 2)).toBe(2880);
  });

  it("should convert days to hours", () => {
    expect(convertToNewDurationType("days", "hours", 2)).toBe(48);
  });

  it("should round up minutes to hours when not evenly divisible", () => {
    expect(convertToNewDurationType("minutes", "hours", 90)).toBe(2);
  });

  it("should round up minutes to days when not evenly divisible", () => {
    expect(convertToNewDurationType("minutes", "days", 1441)).toBe(2);
  });

  it("should round up hours to days when not evenly divisible", () => {
    expect(convertToNewDurationType("hours", "days", 25)).toBe(2);
  });

  it("should return 0 for a zero value in every direction", () => {
    const durationTypes = ["minutes", "hours", "days"] as const;
    for (const prevType of durationTypes) {
      for (const newType of durationTypes) {
        expect(convertToNewDurationType(prevType, newType, 0)).toBe(0);
      }
    }
  });
});
