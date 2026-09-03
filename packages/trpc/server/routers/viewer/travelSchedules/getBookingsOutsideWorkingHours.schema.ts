import { z } from "zod";

export const ZGetBookingsOutsideWorkingHoursInputSchema = z.object({
  startDate: z.coerce.date(),
  endDate: z.coerce.date().optional().nullable(),
  timeZone: z.string(),
});

export type TGetBookingsOutsideWorkingHoursInputSchema = z.infer<
  typeof ZGetBookingsOutsideWorkingHoursInputSchema
>;
