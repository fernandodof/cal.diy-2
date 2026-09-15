import { detectEventTypeScheduleForUser } from "@calcom/features/availability/lib/detectEventTypeScheduleForUser";
import type { DetectEventTypeScheduleForUserInput } from "@calcom/features/availability/lib/detectEventTypeScheduleForUser";

type ScheduleForWorkingHours = {
  availability: { days: number[]; startTime: Date; endTime: Date; date: Date | null }[];
  timeZone: string;
};

/**
 * The schedule a booking should be judged against when deciding whether it falls
 * outside the host's recurring working hours.
 *
 * Follows the same precedence as availability itself - event type schedule, then the
 * host's, then the user's default - so the answer matches the schedule that actually
 * produced the slots.
 *
 * Returns null when there is no real schedule to judge against: detectEventTypeScheduleForUser
 * falls back to a synthetic Mon-Fri 9-5, and flagging against hours the host never set
 * would mark their own availability as unusual.
 */
export function getScheduleForWorkingHours({
  eventType,
  user,
}: DetectEventTypeScheduleForUserInput): ScheduleForWorkingHours | null {
  const hasRealSchedule = Boolean(
    eventType?.schedule ||
      eventType?.hosts?.find((host) => host.user.id === user.id)?.schedule ||
      user.schedules.filter((schedule) => !user.defaultScheduleId || schedule.id === user.defaultScheduleId)[0]
  );

  if (!hasRealSchedule) {
    return null;
  }

  const { schedule } = detectEventTypeScheduleForUser({ eventType, user });

  if (!schedule.availability?.length) {
    return null;
  }

  return {
    availability: schedule.availability,
    timeZone: schedule.timeZone,
  };
}
