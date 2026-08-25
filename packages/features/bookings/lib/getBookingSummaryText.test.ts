import type { TFunction } from "i18next";
import { describe, expect, it } from "vitest";

import dayjs from "@calcom/dayjs";

import { getBookingSummaryText } from "./getBookingSummaryText";

// Labels are what the user actually reads, so assert against real English copy
// rather than raw keys.
const labels: Record<string, string> = {
  what: "What",
  when: "When",
  time: "Time",
  timezone: "Timezone",
  where: "Where",
};
const t = ((key: string) => labels[key] ?? key) as TFunction;

const baseArgs = {
  title: "30 Min Meeting between Alice and Bob",
  date: dayjs.utc("2024-03-15T14:00:00Z"),
  duration: 30,
  timeZone: "America/New_York",
  location: "Cal Video",
  language: "en",
  is24h: false,
  t,
};

describe("getBookingSummaryText", () => {
  it("includes title, date, time range, timezone and location", () => {
    const summary = getBookingSummaryText(baseArgs);
    const lines = summary.split("\n");

    expect(lines).toHaveLength(5);
    expect(lines[0]).toBe("What: 30 Min Meeting between Alice and Bob");
    expect(lines[1]).toContain("When: ");
    expect(lines[1]).toContain("March 15, 2024");
    expect(lines[2]).toBe("Time: 10:00 AM - 10:30 AM");
    expect(lines[3]).toContain("Timezone: ");
    expect(lines[4]).toBe("Where: Cal Video");
  });

  it("renders the time range in the given timezone", () => {
    const summary = getBookingSummaryText({ ...baseArgs, timeZone: "UTC" });
    expect(summary).toContain("Time: 2:00 PM - 2:30 PM");
  });

  it("uses 24h time when is24h is true", () => {
    const summary = getBookingSummaryText({ ...baseArgs, timeZone: "UTC", is24h: true });
    expect(summary).toContain("Time: 14:00 - 14:30");
  });

  it("derives the end time from the duration", () => {
    const summary = getBookingSummaryText({
      ...baseArgs,
      timeZone: "UTC",
      duration: 90,
    });
    expect(summary).toContain("Time: 2:00 PM - 3:30 PM");
  });

  it("omits the location line when there is no location", () => {
    const summary = getBookingSummaryText({ ...baseArgs, location: null });
    const lines = summary.split("\n");

    expect(lines).toHaveLength(4);
    expect(summary).not.toContain("Where:");
  });

  it("omits the location line when the location is an empty string", () => {
    const summary = getBookingSummaryText({ ...baseArgs, location: "" });
    expect(summary).not.toContain("Where:");
  });

  it("keeps a link location intact so it stays clickable when pasted", () => {
    const summary = getBookingSummaryText({
      ...baseArgs,
      location: "https://meet.example.com/abc-defg-hij",
    });
    expect(summary).toContain("Where: https://meet.example.com/abc-defg-hij");
  });

  it("localizes the date for the given language", () => {
    const summary = getBookingSummaryText({ ...baseArgs, language: "de", timeZone: "UTC" });
    expect(summary).toContain("15. März 2024");
  });
});
