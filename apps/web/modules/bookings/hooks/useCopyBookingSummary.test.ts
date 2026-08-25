import { showToast } from "@calcom/ui/components/toast";
import { act, renderHook } from "@testing-library/react";
import type { TFunction } from "i18next";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { useCopyBookingSummary } from "./useCopyBookingSummary";

vi.mock("@calcom/ui/components/toast", () => ({
  showToast: vi.fn(),
}));

const writeText = vi.fn();

Object.defineProperty(navigator, "clipboard", {
  value: { writeText },
  configurable: true,
  writable: true,
});

// The view passes translations through; echoing the key keeps assertions readable.
const t = ((key: string) => key) as unknown as TFunction;

const baseArgs = {
  title: "30 Min Meeting between Alice and Bob",
  startTime: "2026-03-10T14:00:00.000Z",
  duration: 30,
  timeZone: "Europe/London",
  location: "Cal Video",
  locale: "en",
  t,
};

describe("useCopyBookingSummary", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    writeText.mockResolvedValue(undefined);
  });

  it("writes the booking summary to the clipboard", async () => {
    const { result } = renderHook(() => useCopyBookingSummary(baseArgs));

    await act(async () => {
      result.current.copySummary();
    });

    expect(writeText).toHaveBeenCalledTimes(1);
    expect(writeText).toHaveBeenCalledWith(
      [
        "what: 30 Min Meeting between Alice and Bob",
        "when: Tuesday, March 10, 2026, 2:00 PM - 2:30 PM",
        "timezone: Europe/London (Greenwich Mean Time)",
        "where: Cal Video",
      ].join("\n")
    );
  });

  it("shows a success toast once the copy resolves", async () => {
    const { result } = renderHook(() => useCopyBookingSummary(baseArgs));

    await act(async () => {
      result.current.copySummary();
    });

    expect(showToast).toHaveBeenCalledWith("booking_summary_copied", "success");
  });

  it("shows an error toast when the clipboard write is rejected", async () => {
    writeText.mockRejectedValue(new Error("denied"));
    vi.spyOn(console, "error").mockImplementation(() => undefined);

    const { result } = renderHook(() => useCopyBookingSummary(baseArgs));

    await act(async () => {
      result.current.copySummary();
    });

    expect(showToast).toHaveBeenCalledWith("booking_summary_copy_failed", "error");
  });

  it("flips isCopied after a successful copy so the button can confirm", async () => {
    const { result } = renderHook(() => useCopyBookingSummary(baseArgs));

    expect(result.current.isCopied).toBe(false);

    await act(async () => {
      result.current.copySummary();
    });

    expect(result.current.isCopied).toBe(true);
  });

  it("leaves isCopied false when the copy fails", async () => {
    writeText.mockRejectedValue(new Error("denied"));
    vi.spyOn(console, "error").mockImplementation(() => undefined);

    const { result } = renderHook(() => useCopyBookingSummary(baseArgs));

    await act(async () => {
      result.current.copySummary();
    });

    expect(result.current.isCopied).toBe(false);
  });

  it("does nothing while the duration is still unresolved", async () => {
    const { result } = renderHook(() => useCopyBookingSummary({ ...baseArgs, duration: undefined }));

    await act(async () => {
      result.current.copySummary();
    });

    expect(writeText).not.toHaveBeenCalled();
    expect(showToast).not.toHaveBeenCalled();
  });

  it("omits the location line when the booking has no location", async () => {
    const { result } = renderHook(() => useCopyBookingSummary({ ...baseArgs, location: null }));

    await act(async () => {
      result.current.copySummary();
    });

    expect(writeText.mock.calls[0][0]).not.toContain("where:");
  });

  it("copies every date of a recurring booking", async () => {
    const { result } = renderHook(() =>
      useCopyBookingSummary({
        ...baseArgs,
        recurringDates: ["2026-03-10T14:00:00.000Z", "2026-03-17T14:00:00.000Z"],
      })
    );

    await act(async () => {
      result.current.copySummary();
    });

    const copied = writeText.mock.calls[0][0];
    expect(copied).toContain("Tuesday, March 10, 2026, 2:00 PM - 2:30 PM");
    expect(copied).toContain("Tuesday, March 17, 2026, 2:00 PM - 2:30 PM");
  });
});
