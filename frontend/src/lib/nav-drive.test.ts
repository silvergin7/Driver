import { describe, expect, it } from "vitest";
import { driveEnds, shouldDrive, shouldRev, type DriveClick, type RevClick } from "./nav-drive";

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

function plainDrive(overrides: Partial<DriveClick> = {}): DriveClick {
  return {
    ...plainRev(),
    currentPage: false,
    fromMenu: false,
    ...overrides,
  };
}

describe("shouldDrive", () => {
  it("drives a primary click to another page", () => {
    expect(shouldDrive(plainDrive())).toBe(true);
  });

  it("skips the current page, the menu, and reduced motion", () => {
    expect(shouldDrive(plainDrive({ currentPage: true }))).toBe(false);
    expect(shouldDrive(plainDrive({ fromMenu: true }))).toBe(false);
    expect(shouldDrive(plainDrive({ reducedMotion: true }))).toBe(false);
  });

  it("skips modifier clicks", () => {
    expect(shouldDrive(plainDrive({ altKey: true }))).toBe(false);
    expect(shouldDrive(plainDrive({ ctrlKey: true }))).toBe(false);
    expect(shouldDrive(plainDrive({ metaKey: true }))).toBe(false);
    expect(shouldDrive(plainDrive({ shiftKey: true }))).toBe(false);
  });

  it("skips a non-primary button", () => {
    expect(shouldDrive(plainDrive({ button: 1 }))).toBe(false);
    expect(shouldDrive(plainDrive({ button: 2 }))).toBe(false);
  });
});

describe("driveEnds", () => {
  it("starts on the logo and stops under the link", () => {
    expect(
      driveEnds(
        { left: 0, top: 0, width: 1024, height: 64 },
        { left: 24, top: 10, width: 64, height: 44 },
        { left: 200, top: 10, width: 48, height: 44 },
      ),
    ).toEqual({ startX: 42, startY: 24, endX: 210, endY: 46 });
  });

  it("keeps the end inside the row", () => {
    expect(
      driveEnds(
        { left: 100, top: 0, width: 400, height: 64 },
        { left: 100, top: 10, width: 64, height: 44 },
        { left: 80, top: 10, width: 20, height: 44 },
      ).endX,
    ).toBe(0);
    expect(
      driveEnds(
        { left: 0, top: 0, width: 400, height: 64 },
        { left: 0, top: 10, width: 64, height: 44 },
        { left: 500, top: 0, width: 80, height: 44 },
      ).endX,
    ).toBe(372);
  });
});
