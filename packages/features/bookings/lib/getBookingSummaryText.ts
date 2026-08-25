import type { TFunction } from "i18next";

import type { Dayjs } from "@calcom/dayjs";
import dayjs from "@calcom/dayjs";
import { formatToLocalizedDate, formatToLocalizedTime, formatToLocalizedTimezone } from "@calcom/lib/dayjs";

export type GetBookingSummaryTextArgs = {
  /** Resolved event name shown under "What" */
  title: string;
  /** Start of the booking */
  date: Dayjs;
  /** Duration in minutes, used to derive the end time */
  duration: number;
  /** IANA timezone the booking is displayed in */
  timeZone: string;
  /** Location string already resolved for display, if any */
  location?: string | null;
  language: string;
  is24h: boolean;
  t: TFunction;
};

/**
 * Builds the plain-text summary of a booking that the "Copy summary" button puts
 * on the clipboard. Kept free of React so it can be unit tested directly and
 * reused wherever a textual booking recap is needed.
 */
export function getBookingSummaryText({
  title,
  date,
  duration,
  timeZone,
  location,
  language,
  is24h,
  t,
}: GetBookingSummaryTextArgs): string {
  const startTime = formatToLocalizedTime({
    date,
    locale: language,
    hour12: !is24h,
    timeZone,
  });
  const endTime = formatToLocalizedTime({
    date: dayjs(date).add(duration, "m"),
    locale: language,
    hour12: !is24h,
    timeZone,
  });

  const lines = [
    `${t("what")}: ${title}`,
    `${t("when")}: ${formatToLocalizedDate(date, language, "full", timeZone)}`,
    `${t("time")}: ${startTime} - ${endTime}`,
    `${t("timezone")}: ${formatToLocalizedTimezone(date, language, timeZone)}`,
  ];

  if (location) {
    lines.push(`${t("where")}: ${location}`);
  }

  return lines.join("\n");
}
