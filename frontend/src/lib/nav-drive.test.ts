import { describe, expect, it } from "vitest";
import { shouldRev, type RevClick } from "./nav-drive";

function plainRev(overrides: Partial<RevClick> = {}): RevClick {
  return {
    reducedMotion: false,
    altKey: false,
    ctrlKey: false,
    metaKey: false,
    shiftKey: false,
    button: 0,
    ...overrides,
  };
}

describe("shouldRev", () => {
  it("revs a primary click", () => {
    expect(shouldRev(plainRev())).toBe(true);
  });

  it("skips reduced motion, modifiers, and a non-primary button", () => {
    expect(shouldRev(plainRev({ reducedMotion: true }))).toBe(false);
    expect(shouldRev(plainRev({ altKey: true }))).toBe(false);
    expect(shouldRev(plainRev({ ctrlKey: true }))).toBe(false);
    expect(shouldRev(plainRev({ metaKey: true }))).toBe(false);
    expect(shouldRev(plainRev({ shiftKey: true }))).toBe(false);
    expect(shouldRev(plainRev({ button: 2 }))).toBe(false);
  });
});
