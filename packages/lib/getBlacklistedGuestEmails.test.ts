import process from "node:process";
import { afterEach, describe, expect, it } from "vitest";
import { getBlacklistedGuestEmails } from "./getBlacklistedGuestEmails";

describe("getBlacklistedGuestEmails", () => {
  afterEach(() => {
    delete process.env.BLACKLISTED_GUEST_EMAILS;
  });

  it("returns an empty array when the variable is unset or empty", () => {
    delete process.env.BLACKLISTED_GUEST_EMAILS;
    expect(getBlacklistedGuestEmails()).toEqual([]);

    process.env.BLACKLISTED_GUEST_EMAILS = "";
    expect(getBlacklistedGuestEmails()).toEqual([]);
  });

  it("splits on commas with or without a space after them", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = "a@spam.com,b@spam.com";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com", "b@spam.com"]);

    process.env.BLACKLISTED_GUEST_EMAILS = "a@spam.com, b@spam.com";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com", "b@spam.com"]);
  });

  it("trims leading and trailing whitespace", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = "  a@spam.com  ";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com"]);
  });

  it("lowercases entries", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = "A@Spam.com";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com"]);
  });

  it("splits on line breaks and drops empty entries", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = "a@spam.com,\nb@spam.com,,";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com", "b@spam.com"]);

    process.env.BLACKLISTED_GUEST_EMAILS = "a@spam.com\r\nb@spam.com";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com", "b@spam.com"]);
  });
});
