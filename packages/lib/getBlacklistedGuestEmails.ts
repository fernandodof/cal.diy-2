import process from "node:process";
export const getBlacklistedGuestEmails = (): string[] =>
  (process.env.BLACKLISTED_GUEST_EMAILS ?? "")
    .split(/[,\r\n]+/)
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);
