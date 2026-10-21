import { afterEach, describe, expect, it, vi } from "vitest";
import { withDeadline } from "./with-deadline";

describe("withDeadline", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("resolves before the deadline", async () => {
    vi.useFakeTimers();
    const ms = 2000;
    let resolvePromise: (value: string) => void = () => {};
    const promise = new Promise<string>((resolve) => {
      resolvePromise = resolve;
    });
    const result = withDeadline(promise, ms);
    const captured = result.then(
      (value) => value,
      () => "rejected",
    );
    await vi.advanceTimersByTimeAsync(500);
    resolvePromise("ok");
    await vi.advanceTimersByTimeAsync(ms);
    await expect(captured).resolves.toBe("ok");
  });

  it("rejects at the deadline", async () => {
    vi.useFakeTimers();
    const ms = 2000;
    let status = "pending";
    const result = withDeadline(new Promise<string>(() => {}), ms);
    void result.then(
      () => {
        status = "resolved";
      },
      () => {
        status = "rejected";
      },
    );
    await vi.advanceTimersByTimeAsync(ms - 1);
    expect(status).toBe("pending");
    await vi.advanceTimersByTimeAsync(1);
    expect(status).toBe("rejected");
  });

  it("passes a rejection through", async () => {
    vi.useFakeTimers();
    const error = new Error("wallet");
    const result = withDeadline(Promise.reject(error), 2000);
    const captured = result.then(
      () => "resolved",
      (reason: unknown) => reason,
    );
    await vi.advanceTimersByTimeAsync(0);
    await expect(captured).resolves.toBe(error);
  });
});
