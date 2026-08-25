import { describe, expect, it } from "vitest";
import { buildBookingSummary } from "./buildBookingSummary";

const labels = {
  what: "What",
  when: "When",
  timezone: "Timezone",
  where: "Where",
};

const baseArgs = {
  title: "30 Min Meeting between Alice and Bob",
  startTime: "2026-03-10T14:00:00.000Z",
  duration: 30,
  timeZone: "Europe/London",
  location: "Cal Video",
  locale: "en",
  labels,
};

describe("buildBookingSummary", () => {
  it("includes title, date, time range, timezone and location", () => {
    const summary = buildBookingSummary(baseArgs);

    expect(summary).toBe(
      [
        "What: 30 Min Meeting between Alice and Bob",
        "When: Tuesday, March 10, 2026, 2:00 PM - 2:30 PM",
        "Timezone: Europe/London (Greenwich Mean Time)",
        "Where: Cal Video",
      ].join("\n")
    );
  });

  it("renders the time range in the booking's timezone, not UTC", () => {
    const summary = buildBookingSummary({ ...baseArgs, timeZone: "America/New_York" });

    expect(summary).toContain("When: Tuesday, March 10, 2026, 10:00 AM - 10:30 AM");
    expect(summary).toContain("Timezone: America/New_York (Eastern Daylight Time)");
  });

  it("uses a 24h clock when is24h is set", () => {
    const summary = buildBookingSummary({ ...baseArgs, is24h: true, startTime: "2026-03-10T18:00:00.000Z" });

    expect(summary).toContain("When: Tuesday, March 10, 2026, 18:00 - 18:30");
  });

  it("derives the end time from the duration", () => {
    const summary = buildBookingSummary({ ...baseArgs, duration: 90 });

    expect(summary).toContain("2:00 PM - 3:30 PM");
  });

  it("omits the location line when there is no location", () => {
    const summary = buildBookingSummary({ ...baseArgs, location: null });

    expect(summary).not.toContain("Where:");
    expect(summary.split("\n")).toHaveLength(3);
  });

  it("omits the location line when the location is blank", () => {
    const summary = buildBookingSummary({ ...baseArgs, location: "   " });

    expect(summary).not.toContain("Where:");
  });

  it("trims surrounding whitespace from the location", () => {
    const summary = buildBookingSummary({ ...baseArgs, location: "  Cal Video  " });

    expect(summary).toContain("Where: Cal Video");
  });

  it("uses the provided labels so the summary follows the user's language", () => {
    const summary = buildBookingSummary({
      ...baseArgs,
      locale: "pt-BR",
      labels: { what: "O quê", when: "Quando", timezone: "Fuso horário", where: "Onde" },
    });

    expect(summary).toContain("O quê: 30 Min Meeting between Alice and Bob");
    expect(summary).toContain("Quando: ");
    expect(summary).toContain("Fuso horário: Europe/London");
    expect(summary).toContain("Onde: Cal Video");
  });

  it("formats dates using the given locale", () => {
    const summary = buildBookingSummary({ ...baseArgs, locale: "de" });

    expect(summary).toContain("Dienstag, 10. März 2026");
  });

  it("lists every date of a recurring booking, sorted chronologically", () => {
    const summary = buildBookingSummary({
      ...baseArgs,
      recurringDates: ["2026-03-24T14:00:00.000Z", "2026-03-10T14:00:00.000Z", "2026-03-17T14:00:00.000Z"],
    });

    const when = summary.split("\n").slice(1, 4);
    expect(when).toEqual([
      "When: Tuesday, March 10, 2026, 2:00 PM - 2:30 PM",
      "Tuesday, March 17, 2026, 2:00 PM - 2:30 PM",
      "Tuesday, March 24, 2026, 2:00 PM - 2:30 PM",
    ]);
  });

  it("falls back to startTime when the recurring dates list is empty", () => {
    const summary = buildBookingSummary({ ...baseArgs, recurringDates: [] });

    expect(summary).toContain("When: Tuesday, March 10, 2026, 2:00 PM - 2:30 PM");
  });

  it("accepts a Date instance as the start time", () => {
    const summary = buildBookingSummary({ ...baseArgs, startTime: new Date("2026-03-10T14:00:00.000Z") });

    expect(summary).toContain("When: Tuesday, March 10, 2026, 2:00 PM - 2:30 PM");
  });

  it("keeps each field on its own line so the summary stays pasteable", () => {
    const lines = buildBookingSummary(baseArgs).split("\n");

    expect(lines).toHaveLength(4);
    expect(lines.every((line) => line.trim().length > 0)).toBe(true);
  });
});
