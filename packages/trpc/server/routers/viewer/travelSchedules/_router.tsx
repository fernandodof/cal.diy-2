import authedProcedure from "../../../procedures/authedProcedure";
import { router } from "../../../trpc";
import { ZGetBookingsOutsideWorkingHoursInputSchema } from "./getBookingsOutsideWorkingHours.schema";

export const travelSchedulesRouter = router({
  get: authedProcedure.query(async ({ ctx }) => {
    const handler = (await import("./getTravelSchedules.handler")).getTravelSchedulesHandler;
    return handler({ ctx });
  }),
  getBookingsOutsideWorkingHours: authedProcedure
    .input(ZGetBookingsOutsideWorkingHoursInputSchema)
    .query(async ({ ctx, input }) => {
      const handler = (await import("./getBookingsOutsideWorkingHours.handler"))
        .getBookingsOutsideWorkingHoursHandler;
      return handler({ ctx, input });
    }),
});
