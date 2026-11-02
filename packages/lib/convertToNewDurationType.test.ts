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
});
