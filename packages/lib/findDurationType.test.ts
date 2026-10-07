import { describe, it, expect } from "vitest";

import findDurationType from "./findDurationType";

describe("findDurationType", () => {
  it("should return days for a value divisible by the minutes in a day", () => {
    expect(findDurationType(1440)).toBe("days");
    expect(findDurationType(2880)).toBe("days");
  });

  it("should return hours for a value divisible by the minutes in an hour but not a day", () => {
    expect(findDurationType(60)).toBe("hours");
    expect(findDurationType(120)).toBe("hours");
    expect(findDurationType(1500)).toBe("hours");
  });

  it("should return minutes for any other value", () => {
    expect(findDurationType(1)).toBe("minutes");
    expect(findDurationType(30)).toBe("minutes");
    expect(findDurationType(90)).toBe("minutes");
  });

  it("should return days for zero, which is divisible by both", () => {
    expect(findDurationType(0)).toBe("days");
  });
});
