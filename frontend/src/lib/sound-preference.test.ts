import { describe, expect, it } from "vitest";
import { persistSoundEnabled, soundEnabledFromStorage } from "./sound-preference";

describe("soundEnabledFromStorage", () => {
  it("reads on only for the string on", () => {
    expect(soundEnabledFromStorage(() => "on")).toBe(true);
  });

  it("reads off for any other stored value", () => {
    expect(soundEnabledFromStorage(() => null)).toBe(false);
    expect(soundEnabledFromStorage(() => "off")).toBe(false);
    expect(soundEnabledFromStorage(() => "")).toBe(false);
    expect(soundEnabledFromStorage(() => "yes")).toBe(false);
    expect(soundEnabledFromStorage(() => "ON")).toBe(false);
  });

  it("reads off when storage throws", () => {
    expect(
      soundEnabledFromStorage(() => {
        throw new Error("blocked");
      }),
    ).toBe(false);
  });
});

describe("persistSoundEnabled", () => {
  it("writes on and off", () => {
    const values: string[] = [];
    expect(
      persistSoundEnabled(true, (value) => {
        values.push(value);
      }),
    ).toBe(true);
    expect(
      persistSoundEnabled(false, (value) => {
        values.push(value);
      }),
    ).toBe(true);
    expect(values).toEqual(["on", "off"]);
  });

  it("reports a write failure", () => {
    expect(
      persistSoundEnabled(true, () => {
        throw new Error("full");
      }),
    ).toBe(false);
  });
});
