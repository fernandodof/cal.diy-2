import { describe, it, expect } from "vitest";

import convertToNewDurationType from "./convertToNewDurationType";

describe("convertToNewDurationType", () => {
  it("returns the value unchanged when converting minutes to minutes", () => {
    expect(convertToNewDurationType("minutes", "minutes", 45)).toBe(45);
  });

  it("returns the value unchanged when converting hours to hours", () => {
    expect(convertToNewDurationType("hours", "hours", 5)).toBe(5);
  });

  it("returns the value unchanged when converting days to days", () => {
    expect(convertToNewDurationType("days", "days", 3)).toBe(3);
  });

  it("converts minutes to hours", () => {
    expect(convertToNewDurationType("minutes", "hours", 120)).toBe(2);
  });

  it("converts minutes to days", () => {
    expect(convertToNewDurationType("minutes", "days", 2880)).toBe(2);
  });

  it("converts hours to minutes", () => {
    expect(convertToNewDurationType("hours", "minutes", 2)).toBe(120);
  });

  it("converts hours to days", () => {
    expect(convertToNewDurationType("hours", "days", 48)).toBe(2);
  });

  it("converts days to minutes", () => {
    expect(convertToNewDurationType("days", "minutes", 2)).toBe(2880);
  });

  it("converts days to hours", () => {
    expect(convertToNewDurationType("days", "hours", 2)).toBe(48);
  });

  it("rounds up when minutes do not divide evenly into hours", () => {
    expect(convertToNewDurationType("minutes", "hours", 90)).toBe(2);
  });

  it("rounds up when minutes do not divide evenly into days", () => {
    expect(convertToNewDurationType("minutes", "days", 1441)).toBe(2);
  });

  it("rounds up when hours do not divide evenly into days", () => {
    expect(convertToNewDurationType("hours", "days", 25)).toBe(2);
  });

  it("returns 0 for a zero value in every direction", () => {
    const durationTypes = ["minutes", "hours", "days"] as const;
    for (const prevType of durationTypes) {
      for (const newType of durationTypes) {
        expect(convertToNewDurationType(prevType, newType, 0)).toBe(0);
      }
    }
  });
});
