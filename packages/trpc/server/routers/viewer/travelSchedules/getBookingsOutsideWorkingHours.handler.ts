import { getBookingsOutsideWorkingHours } from "@calcom/features/travelSchedule/lib/getBookingsOutsideWorkingHours";
import { TravelScheduleRepository } from "@calcom/features/travelSchedule/repositories/TravelScheduleRepository";
import type { TrpcSessionUser } from "@calcom/trpc/server/types";
import type { TGetBookingsOutsideWorkingHoursInputSchema } from "./getBookingsOutsideWorkingHours.schema";

type GetBookingsOutsideWorkingHoursOptions = {
  ctx: {
    user: NonNullable<TrpcSessionUser>;
  };
  input: TGetBookingsOutsideWorkingHoursInputSchema;
};

/**
 * Advisory lookahead for the travel-schedule flow: which confirmed bookings
 * would sit outside the host's working hours once this trip applies.
 *
 * Read-only by design — bookings are never moved or cancelled on the user's
 * behalf; the host is simply warned while they can still act.
 */
export const getBookingsOutsideWorkingHoursHandler = async ({
  ctx,
  input,
}: GetBookingsOutsideWorkingHoursOptions) => {
  const { startDate, endDate, timeZone } = input;

  const lookaheadData = await TravelScheduleRepository.findWorkingHoursLookaheadData({
    userId: ctx.user.id,
    dateFrom: startDate,
    dateTo: endDate ?? undefined,
  });

  if (!lookaheadData) return { bookings: [] };

  const bookings = getBookingsOutsideWorkingHours({
    bookings: lookaheadData.bookings,
    availability: lookaheadData.availability,
    timeZone: lookaheadData.timeZone,
    travelSchedule: { startDate, endDate, timeZone },
    existingTravelSchedules: lookaheadData.travelSchedules,
  });

  return { bookings };
};
