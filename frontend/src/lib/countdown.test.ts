import { describe, expect, it } from "vitest";
import { formatCountdown } from "./countdown";

const hour = 3600n;
const day = 24n * hour;

describe("formatCountdown", () => {
  it("formats zero seconds as 00:00:00", () => {
    expect(formatCountdown(100n, 100n)).toBe("00:00:00");
  });

  it("formats hours, minutes, and seconds under 24 hours", () => {
    expect(formatCountdown(hour + 2n * 60n + 3n, 0n)).toBe("01:02:03");
  });

  it("formats exactly 24 hours as 24:00:00", () => {
    expect(formatCountdown(day, 0n)).toBe("24:00:00");
  });

  it("formats a remaining time longer than 24 hours", () => {
    expect(formatCountdown(day + hour, 0n)).toBe("25:00:00");
  });

  it("shows 00:00:00 once the target time has passed", () => {
    expect(formatCountdown(100n, 101n)).toBe("00:00:00");
  });
});
