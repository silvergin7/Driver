import { describe, expect, it } from "vitest";
import { formatCountdown } from "./countdown";

const minute = 60n;
const hour = 60n * minute;
const day = 24n * hour;

describe("formatCountdown", () => {
  it("formats zero seconds as less than a minute", () => {
    expect(formatCountdown(100n, 100n)).toBe("less than a minute");
  });

  it("formats 59 seconds as less than a minute", () => {
    expect(formatCountdown(59n, 0n)).toBe("less than a minute");
  });

  it("formats 60 seconds as 1 minute", () => {
    expect(formatCountdown(minute, 0n)).toBe("1 minute");
  });

  it("formats 61 seconds as 1 minute", () => {
    expect(formatCountdown(minute + 1n, 0n)).toBe("1 minute");
  });

  it("formats 1 hour", () => {
    expect(formatCountdown(hour, 0n)).toBe("1 hour");
  });

  it("formats 1 day", () => {
    expect(formatCountdown(day, 0n)).toBe("1 day");
  });

  it("formats 1 day 1 hour 1 minute", () => {
    expect(formatCountdown(day + hour + minute, 0n)).toBe("1 day 1 hour 1 minute");
  });

  it("formats 1 day 5 minutes", () => {
    expect(formatCountdown(day + 5n * minute, 0n)).toBe("1 day 5 minutes");
  });

  it("formats 2 days 3 hours", () => {
    expect(formatCountdown(2n * day + 3n * hour, 0n)).toBe("2 days 3 hours");
  });

  it("formats exactly 30 days", () => {
    expect(formatCountdown(30n * day, 0n)).toBe("30 days");
  });

  it("floors 29 days 23 hours 59 minutes 59 seconds", () => {
    expect(formatCountdown(29n * day + 23n * hour + 59n * minute + 59n, 0n)).toBe(
      "29 days 23 hours 59 minutes",
    );
  });

  it("formats a passed target as less than a minute", () => {
    expect(formatCountdown(100n, 101n)).toBe("less than a minute");
  });
});
