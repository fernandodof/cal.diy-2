import process from "node:process";
import { describe, expect, it } from "vitest";
import { getBlacklistedGuestEmails, getBlacklistedGuestEmailsAsWritten } from "./getBlacklistedGuestEmails";

describe("getBlacklistedGuestEmails", () => {
  it("returns an empty array when the variable is unset or empty", () => {
    delete process.env.BLACKLISTED_GUEST_EMAILS;
    expect(getBlacklistedGuestEmails()).toEqual([]);

    process.env.BLACKLISTED_GUEST_EMAILS = "";
    expect(getBlacklistedGuestEmails()).toEqual([]);
    delete process.env.BLACKLISTED_GUEST_EMAILS;
  });

  it("splits on commas with or without a space after them", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = "a@spam.com,b@spam.com";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com", "b@spam.com"]);

    process.env.BLACKLISTED_GUEST_EMAILS = "a@spam.com, b@spam.com";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com", "b@spam.com"]);
    delete process.env.BLACKLISTED_GUEST_EMAILS;
  });

  it("trims leading and trailing whitespace", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = "  a@spam.com  ";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com"]);
    delete process.env.BLACKLISTED_GUEST_EMAILS;
  });

  it("lowercases entries", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = "A@Spam.com";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com"]);
    delete process.env.BLACKLISTED_GUEST_EMAILS;
  });

  it("splits on line breaks and drops empty entries", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = "a@spam.com,\nb@spam.com,,";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com", "b@spam.com"]);

    process.env.BLACKLISTED_GUEST_EMAILS = "a@spam.com\r\nb@spam.com";
    expect(getBlacklistedGuestEmails()).toEqual(["a@spam.com", "b@spam.com"]);
    delete process.env.BLACKLISTED_GUEST_EMAILS;
  });
});

describe("getBlacklistedGuestEmailsAsWritten", () => {
  it("parses the same way but keeps the casing entries were written with", () => {
    process.env.BLACKLISTED_GUEST_EMAILS = " Foo@Spam.com,\nb@spam.com,,";
    expect(getBlacklistedGuestEmailsAsWritten()).toEqual(["Foo@Spam.com", "b@spam.com"]);
    delete process.env.BLACKLISTED_GUEST_EMAILS;
  });
});
