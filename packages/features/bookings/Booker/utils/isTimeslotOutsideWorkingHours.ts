import dayjs from "@calcom/dayjs";

import { isSlotEquivalent, isValidISOFormat } from "./isSlotEquivalent";

type Maybe<T> = T | undefined;

// Format is YYYY-MM-DD
type DateInBookerTimeZone = string;

// Format is YYYY-MM-DDTHH:mm:ssZ
type SlotInIsoFormat = string;
type SlotsInIso = { time: SlotInIsoFormat; isOutsideWorkingHours?: boolean }[];
type ScheduleData = {
  slots: Record<DateInBookerTimeZone, SlotsInIso>;
};

function _findSlot(slotsInIsoForDate: Maybe<SlotsInIso>, slotToCheckInIso: SlotInIsoFormat) {
  return slotsInIsoForDate?.find((slot) =>
    isSlotEquivalent({ slotTimeInIso: slot.time, slotToCheckInIso })
  );
}

/**
 * Whether the selected slot falls outside the schedule's recurring weekly hours, i.e.
 * it is only bookable because a date override opened it. The flag is computed
 * server-side in the slots handler and read back off the slot here.
 *
 * Advisory only - a false negative just means no notice is shown.
 */
export const isTimeSlotOutsideWorkingHours = ({
  scheduleData,
  slotToCheckInIso,
}: {
  scheduleData: ScheduleData | null;
  slotToCheckInIso: SlotInIsoFormat;
}): boolean => {
  if (!scheduleData) return false;

  const dateInGMT = isValidISOFormat(slotToCheckInIso) ? slotToCheckInIso.split("T")[0] : null;
  if (!dateInGMT) return false;

  // The booker's timezone can put the slot under the previous or next date key, the
  // same way isTimeSlotAvailable has to look either side of the date.
  const dateBefore = dayjs(dateInGMT).subtract(1, "day").format("YYYY-MM-DD");
  const dateAfter = dayjs(dateInGMT).add(1, "day").format("YYYY-MM-DD");

  const slot =
    _findSlot(scheduleData.slots[dateInGMT], slotToCheckInIso) ??
    _findSlot(scheduleData.slots[dateBefore], slotToCheckInIso) ??
    _findSlot(scheduleData.slots[dateAfter], slotToCheckInIso);

  return slot?.isOutsideWorkingHours === true;
};
