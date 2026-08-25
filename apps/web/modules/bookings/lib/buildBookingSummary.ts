import type { ConfigType } from "@calcom/dayjs";
import dayjs from "@calcom/dayjs";
import { formatToLocalizedDate, formatToLocalizedTime, formatToLocalizedTimezone } from "@calcom/lib/dayjs";

export type BuildBookingSummaryArgs = {
  /** Event title as shown in the "What" row. */
  title: string;
  /** Start of the booking. Additional dates are used for recurring bookings. */
  startTime: ConfigType;
  /** Duration in minutes, used to derive the end time. */
  duration: number;
  /** Timezone the booking is displayed in. */
  timeZone: string;
  /** Location as shown in the "Where" row. Omitted from the summary when empty. */
  location?: string | null;
  /** Locale used for date/time formatting. */
  locale?: string;
  /** Whether times are rendered in a 24h clock. */
  is24h?: boolean;
  /** Remaining dates of a recurring booking, replacing `startTime` when present. */
  recurringDates?: ConfigType[] | null;
  /** Labels so the summary follows the user's language, matching the on-screen rows. */
  labels: {
    what: string;
    when: string;
    timezone: string;
    where: string;
  };
};

function formatDateRange({
  date,
  duration,
  locale,
  is24h,
  timeZone,
}: {
  date: dayjs.Dayjs;
  duration: number;
  locale?: string;
  is24h: boolean;
  timeZone: string;
}) {
  const day = formatToLocalizedDate(date, locale, "full", timeZone);
  const start = formatToLocalizedTime({ date, locale, hour12: !is24h, timeZone });
  const end = formatToLocalizedTime({
    date: date.add(duration, "m"),
    locale,
    hour12: !is24h,
    timeZone,
  });

  return `${day}, ${start} - ${end}`;
}

/**
 * Builds the plain-text summary copied by the "Copy summary" button on the
 * booking confirmation screen. Kept free of React/browser APIs so the exact
 * text can be asserted in unit tests.
 */
export function buildBookingSummary({
  title,
  startTime,
  duration,
  timeZone,
  location,
  locale,
  is24h = false,
  recurringDates,
  labels,
}: BuildBookingSummaryArgs): string {
  const dates =
    recurringDates && recurringDates.length > 0
      ? [...recurringDates].sort((a, b) => (dayjs(a).isAfter(dayjs(b)) ? 1 : -1))
      : [startTime];

  const when = dates
    .map((date) => formatDateRange({ date: dayjs(date).tz(timeZone), duration, locale, is24h, timeZone }))
    .join("\n");

  const lines = [`${labels.what}: ${title}`, `${labels.when}: ${when}`];

  const timezoneLabel = formatToLocalizedTimezone(dayjs(dates[0]), locale, timeZone);
  if (timezoneLabel) {
    lines.push(`${labels.timezone}: ${timeZone} (${timezoneLabel})`);
  } else {
    lines.push(`${labels.timezone}: ${timeZone}`);
  }

  const trimmedLocation = location?.trim();
  if (trimmedLocation) {
    lines.push(`${labels.where}: ${trimmedLocation}`);
  }

  return lines.join("\n");
}
