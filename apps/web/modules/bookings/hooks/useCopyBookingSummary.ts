import { useCopy } from "@calcom/lib/hooks/useCopy";
import { showToast } from "@calcom/ui/components/toast";
import type { TFunction } from "i18next";
import type { BuildBookingSummaryArgs } from "../lib/buildBookingSummary";
import { buildBookingSummary } from "../lib/buildBookingSummary";

type UseCopyBookingSummaryArgs = Omit<BuildBookingSummaryArgs, "duration" | "labels"> & {
  /** Undefined while the duration is still being resolved; copying is a no-op until then. */
  duration: number | undefined;
  t: TFunction;
};

/**
 * Wires the booking summary text to the clipboard and surfaces the result as a toast.
 */
export function useCopyBookingSummary({ duration, t, ...summaryArgs }: UseCopyBookingSummaryArgs) {
  const { isCopied, copyToClipboard } = useCopy();

  const copySummary = () => {
    if (!duration) return;

    const summary = buildBookingSummary({
      ...summaryArgs,
      duration,
      labels: {
        what: t("what"),
        when: t("when"),
        timezone: t("timezone"),
        where: t("where"),
      },
    });

    copyToClipboard(summary, {
      onSuccess: () => showToast(t("booking_summary_copied"), "success"),
      onFailure: () => showToast(t("booking_summary_copy_failed"), "error"),
    });
  };

  return { isCopied, copySummary };
}
