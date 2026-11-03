import process from "node:process";

// Trimmed, non-empty entries, in the casing they were written with.
export const getBlacklistedGuestEmailsAsWritten = (): string[] =>
  (process.env.BLACKLISTED_GUEST_EMAILS ?? "")
    .split(/[,\r\n]+/)
    .map((email) => email.trim())
    .filter(Boolean);

// Trimmed, non-empty, lowercased entries.
export const getBlacklistedGuestEmails = (): string[] =>
  getBlacklistedGuestEmailsAsWritten().map((email) => email.toLowerCase());
