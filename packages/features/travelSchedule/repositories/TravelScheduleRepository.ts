import dayjs from "@calcom/dayjs";
import { prisma } from "@calcom/prisma";
import { BookingStatus } from "@calcom/prisma/enums";

export class TravelScheduleRepository {
  static async findTravelSchedulesByUserId(userId: number) {
    const allTravelSchedules = await prisma.travelSchedule.findMany({
      where: {
        userId,
      },
      select: {
        id: true,
        startDate: true,
        endDate: true,
        timeZone: true,
      },
    });

    return allTravelSchedules;
  }

  /**
   * Everything needed to tell a host, while they are still picking trip dates,
   * which of their upcoming bookings would land outside their working hours.
   */
  static async findWorkingHoursLookaheadData({
    userId,
    dateFrom,
    dateTo,
  }: {
    userId: number;
    dateFrom: Date;
    dateTo?: Date;
  }) {
    const [user, bookings, travelSchedules] = await Promise.all([
      prisma.user.findUnique({
        where: { id: userId },
        select: {
          timeZone: true,
          defaultScheduleId: true,
        },
      }),
      prisma.booking.findMany({
        where: {
          userId,
          status: BookingStatus.ACCEPTED,
          startTime: {
            gte: dayjs(dateFrom).startOf("day").toDate(),
            ...(dateTo ? { lte: dayjs(dateTo).endOf("day").toDate() } : {}),
          },
        },
        select: {
          uid: true,
          title: true,
          startTime: true,
          endTime: true,
        },
        orderBy: { startTime: "asc" },
      }),
      TravelScheduleRepository.findTravelSchedulesByUserId(userId),
    ]);

    if (!user) return null;

    const schedule = user.defaultScheduleId
      ? await prisma.schedule.findFirst({
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
        })
      : null;

    return {
      timeZone: schedule?.timeZone ?? user.timeZone,
      availability: schedule?.availability ?? [],
      bookings,
      travelSchedules,
    };
  }
}
