import dayjs from "@calcom/dayjs";
import logger from "@calcom/lib/logger";
import { safeStringify } from "@calcom/lib/safeStringify";
import type { PrismaClient } from "@calcom/prisma";
import { BookingStatus } from "@calcom/prisma/enums";

import { isOutsideRecurringHours } from "./isOutsideRecurringHours";

const log = logger.getSubLogger({ prefix: ["flagBookingsOutsideWorkingHours"] });

type BookingToFlag = {
  startTime: string;
  endTime: string;
  status: BookingStatus;
};

/**
 * Marks bookings that fall outside the viewer's recurring working hours, i.e. the
 * ones only bookable because a date override opened that time.
 *
 * The viewer's own schedule is the reference even for team events - it is their
 * booking list, so it answers "is this outside *my* hours".
 *
 * Computed on read rather than stored, so it only describes upcoming bookings:
 * editing a schedule re-judges the bookings that have not happened yet.
 */
export async function flagBookingsOutsideWorkingHours<TBooking extends BookingToFlag>({
  bookings,
  userId,
  prisma,
}: {
  bookings: TBooking[];
  userId: number;
  prisma: PrismaClient;
}): Promise<(TBooking & { isOutsideWorkingHours: boolean })[]> {
  const schedule = await getViewerRecurringSchedule({ userId, prisma }).catch((error) => {
    // The badge is advisory, so a failed lookup should not take the list down with it.
    log.warn("Could not load the viewer's schedule, skipping working hours flags", safeStringify(error));
    return null;
  });

  if (!schedule) {
    return bookings.map((booking) => ({ ...booking, isOutsideWorkingHours: false }));
  }

  return bookings.map((booking) => ({
    ...booking,
    isOutsideWorkingHours:
      booking.status !== BookingStatus.CANCELLED &&
      booking.status !== BookingStatus.REJECTED &&
      isOutsideRecurringHours({
        start: dayjs.utc(booking.startTime),
        end: dayjs.utc(booking.endTime),
        availability: schedule.availability,
        timeZone: schedule.timeZone,
      }),
  }));
}

/**
 * The viewer's default schedule, fetched once per request rather than per booking.
 */
async function getViewerRecurringSchedule({ userId, prisma }: { userId: number; prisma: PrismaClient }) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      timeZone: true,
      defaultScheduleId: true,
    },
  });

  if (!user?.defaultScheduleId) {
    return null;
  }

  const schedule = await prisma.schedule.findFirst({
    where: { id: user.defaultScheduleId, userId },
    select: {
      timeZone: true,
      availability: {
        select: {
          days: true,
          startTime: true,
          endTime: true,
          date: true,
        },
      },
    },
  });

  if (!schedule) {
    return null;
  }

  return {
    availability: schedule.availability,
    timeZone: schedule.timeZone ?? user.timeZone,
  };
}
