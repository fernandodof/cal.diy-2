import type { Dayjs } from "@calcom/dayjs";
import dayjs from "@calcom/dayjs";
import type { DateOverride, WorkingHours } from "@calcom/features/schedules/lib/date-ranges";
import { buildDateRanges } from "@calcom/features/schedules/lib/date-ranges";

export type TravelScheduleInput = {
  startDate: Date;
  endDate?: Date | null;
  timeZone: string;
};

export type BookingForLookahead = {
  uid: string;
  title: string;
  startTime: Date;
  endTime: Date;
};

export type BookingOutsideWorkingHours = BookingForLookahead & {
  /** The timezone the booking was evaluated against, i.e. the trip's timezone. */
  timeZone: string;
};

/**
 * Returns the confirmed bookings that would fall outside the user's working
 * hours once `travelSchedule` is applied.
 *
 * This is advisory only: per the fork's working-hours decisions, nothing here
 * mutates or cancels a booking. Confirmed bookings never move; the host is
 * warned early — while picking the trip dates — so they can still act.
 */
export function getBookingsOutsideWorkingHours({
  bookings,
  availability,
  timeZone,
  travelSchedule,
  existingTravelSchedules = [],
}: {
  bookings: BookingForLookahead[];
  availability: (DateOverride | WorkingHours)[];
  /** The user's current (non-travel) timezone. */
  timeZone: string;
  travelSchedule: TravelScheduleInput;
  /** Already-saved travel schedules, so overlapping trips resolve consistently. */
  existingTravelSchedules?: TravelScheduleInput[];
}): BookingOutsideWorkingHours[] {
  const tripStart = dayjs(travelSchedule.startDate).startOf("day");
  const tripEnd = travelSchedule.endDate ? dayjs(travelSchedule.endDate).endOf("day") : null;

  const bookingsDuringTrip = bookings.filter((booking) => {
    const start = dayjs(booking.startTime);
    if (start.isBefore(tripStart)) return false;
    return !tripEnd || !start.isAfter(tripEnd);
  });

  if (!bookingsDuringTrip.length) return [];

  // Look as far as the bookings we actually have to check, but widen to whole
  // days in the destination timezone. buildDateRanges clamps each day's window
  // to dateFrom/dateTo, so a window ending exactly at a booking's end instant
  // would truncate that day's working hours to the booking itself and report it
  // as outside them. Crossing the dateline makes this routine: a booking can
  // land on the day after the trip's last local day.
  const firstBookingStart = bookingsDuringTrip.reduce(
    (earliest, booking) => (dayjs(booking.startTime).isBefore(earliest) ? dayjs(booking.startTime) : earliest),
    dayjs(bookingsDuringTrip[0].startTime)
  );
  const latestBookingEnd = bookingsDuringTrip.reduce(
    (latest, booking) => (dayjs(booking.endTime).isAfter(latest) ? dayjs(booking.endTime) : latest),
    tripStart
  );

  const dateFrom = dayjs.min(tripStart, firstBookingStart.tz(travelSchedule.timeZone).startOf("day"));
  const dateTo = latestBookingEnd.tz(travelSchedule.timeZone).endOf("day");

  const toDayjsTravelSchedule = (schedule: TravelScheduleInput) => ({
    startDate: dayjs(schedule.startDate).startOf("day"),
    endDate: schedule.endDate ? dayjs(schedule.endDate).endOf("day") : undefined,
    timeZone: schedule.timeZone,
  });

  const { dateRanges } = buildDateRanges({
    availability,
    timeZone,
    dateFrom,
    dateTo,
    travelSchedules: [...existingTravelSchedules, travelSchedule].map(toDayjsTravelSchedule),
  });

  return bookingsDuringTrip
    .filter((booking) => !isFullyWithinRanges(dayjs(booking.startTime), dayjs(booking.endTime), dateRanges))
    .map((booking) => ({ ...booking, timeZone: travelSchedule.timeZone }));
}

function isFullyWithinRanges(start: Dayjs, end: Dayjs, ranges: { start: Dayjs; end: Dayjs }[]) {
  return ranges.some((range) => !start.isBefore(range.start) && !end.isAfter(range.end));
}
