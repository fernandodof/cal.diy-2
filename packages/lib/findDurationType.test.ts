import { describe, it, expect } from "vitest";

import findDurationType from "./findDurationType";

describe("findDurationType", () => {
  it("returns days for a value divisible by 1440", () => {
    expect(findDurationType(1440)).toBe("days");
    expect(findDurationType(2880)).toBe("days");
  });

  it("returns hours for a value divisible by 60 but not 1440", () => {
    expect(findDurationType(60)).toBe("hours");
    expect(findDurationType(120)).toBe("hours");
    expect(findDurationType(1500)).toBe("hours");
  });

  it("returns minutes for a value not divisible by 60", () => {
    expect(findDurationType(1)).toBe("minutes");
    expect(findDurationType(45)).toBe("minutes");
    expect(findDurationType(90)).toBe("minutes");
  });

  it("returns days for 0", () => {
    expect(findDurationType(0)).toBe("days");
  });
});
