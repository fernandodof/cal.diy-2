import type { ConfigType, Dayjs } from "@calcom/dayjs";
import dayjs from "@calcom/dayjs";

/**
 * Business hours used to flag bookings that land outside of a typical working day.
 * Evaluated in the organizer's timezone, not the attendee's, so that a booker in
 * another timezone gets warned when they are about to book someone's night.
 */
export const BUSINESS_HOURS = {
  /** Minutes from midnight at which the business day starts (09:00). */
  startMinute: 9 * 60,
  /** Minutes from midnight at which the business day ends (18:00). */
  endMinute: 18 * 60,
  /** Days of the week considered business days, following dayjs' `day()` (0 = Sunday). */
  days: [1, 2, 3, 4, 5],
} as const;

const toMinutes = (date: Dayjs) => date.hour() * 60 + date.minute();

/**
 * Returns true when the given instant falls outside business hours in `timeZone`.
 * An unknown/invalid timezone falls back to the instant's own offset.
 */
export const isOutsideBusinessHours = (date: ConfigType, timeZone?: string | null): boolean => {
  const parsed = dayjs(date);
  if (!parsed.isValid()) return false;

  let localDate = parsed;
  if (timeZone) {
    try {
      localDate = parsed.tz(timeZone);
    } catch {
      // Unknown timezone: fall back to the instant's own offset rather than skipping the check.
    }
  }

  if (!BUSINESS_HOURS.days.includes(localDate.day() as (typeof BUSINESS_HOURS.days)[number])) return true;

  const minute = toMinutes(localDate);
  return minute < BUSINESS_HOURS.startMinute || minute >= BUSINESS_HOURS.endMinute;
};

/** Formats the business hours window for display, honouring the user's 12/24h preference. */
export const getBusinessHoursRange = (timeFormat: 12 | 24 = 24) => {
  const format = timeFormat === 12 ? "h:mma" : "HH:mm";
  const base = dayjs().startOf("day");
  return {
    start: base.add(BUSINESS_HOURS.startMinute, "minute").format(format),
    end: base.add(BUSINESS_HOURS.endMinute, "minute").format(format),
  };
};
