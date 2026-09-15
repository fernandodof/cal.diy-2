import type { Dayjs } from "@calcom/dayjs";
import type { Availability } from "@calcom/prisma/client";

type AvailabilityRow = Pick<Availability, "days" | "startTime" | "endTime" | "date">;
type RecurringAvailability = Pick<Availability, "days" | "startTime" | "endTime">;

/**
 * Availability holds both recurring weekly rows and date overrides, told apart by
 * `date`. Keep only the recurring ones — they are the host's normal working hours,
 * before any override widened them.
 */
export function getRecurringAvailability(availability: AvailabilityRow[]): RecurringAvailability[] {
  return availability.filter((item) => !item.date && item.days.length > 0);
}

/**
 * Whether a booking falls outside the host's recurring weekly availability, i.e. it
 * is only bookable because a date override opened that time.
 *
 * Deliberately not a judgement about the hour of day: a 7am booking inside the
 * recurring rows is not outside working hours, and a 10am booking that only exists
 * because of an override is.
 *
 * Availability that has been widened by an override is already merged into the
 * dateRanges every bookable slot is checked against, so the comparison has to be
 * against the recurring rows instead - see buildDateRanges in
 * packages/features/schedules/lib/date-ranges.ts.
 */
export function isOutsideRecurringHours({
  start,
  end,
  availability,
  timeZone,
}: {
  start: Dayjs;
  end: Dayjs;
  availability: AvailabilityRow[];
  timeZone: string;
}): boolean {
  const recurringAvailability = getRecurringAvailability(availability);

  // No recurring rows means no baseline to judge against. Flag nothing rather than
  // flag everything against working hours the host never set.
  if (!recurringAvailability.length) {
    return false;
  }

  const startInTz = start.tz(timeZone);
  const endInTz = end.tz(timeZone);

  return !recurringAvailability.some((item) => {
    if (!item.days.includes(startInTz.day())) {
      return false;
    }

    const dayStart = startInTz.startOf("day");

    const windowStart = dayStart
      .add(item.startTime.getUTCHours(), "hours")
      .add(item.startTime.getUTCMinutes(), "minutes");

    let windowEnd = dayStart
      .add(item.endTime.getUTCHours(), "hours")
      .add(item.endTime.getUTCMinutes(), "minutes");

    // Availability can only be set up to 11:59PM, which would otherwise leave the
    // last minute of the day outside the window.
    if (windowEnd.hour() === 23 && windowEnd.minute() === 59) {
      windowEnd = windowEnd.add(1, "minute");
    }

    // Contained in a single window, matching hasDateRangeForBooking in
    // packages/features/bookings/lib/handleNewBooking/ensureAvailableUsers.ts.
    return !startInTz.isBefore(windowStart) && !endInTz.isAfter(windowEnd);
  });
}
