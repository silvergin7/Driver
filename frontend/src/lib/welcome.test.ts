import { describe, expect, it } from "vitest";
import {
  focusAfterTab,
  welcomeCopy,
  welcomeDecision,
  welcomeSeenValue,
} from "./welcome";

describe("welcomeCopy", () => {
  it("uses the launch wording on every chain", () => {
    expect(welcomeCopy.title).toBe("Welcome to Driver");
    expect(welcomeCopy.text).toBe(
      "Driver is a learning project on Ethereum mainnet. Its tokens have no real value, but every action here costs real gas. Want to see how it all works first, for free?",
    );
    expect(welcomeCopy.trySimulation).toBe("Try the simulation");
    expect(welcomeCopy.enterSite).toBe("Enter the live site");
  });
});

describe("welcomeDecision", () => {
  it("shows on a first visit and stays hidden once it has been seen", () => {
    expect(welcomeDecision("/", null)).toBe(true);
    expect(welcomeDecision("/game", null)).toBe(true);
    expect(welcomeDecision("/", welcomeSeenValue)).toBe(false);
  });

  it("never shows on the simulation page", () => {
    expect(welcomeDecision("/simulation", null)).toBe(false);
    expect(welcomeDecision("/simulation", welcomeSeenValue)).toBe(false);
  });
});

describe("focusAfterTab", () => {
  it("wraps at both ends", () => {
    expect(focusAfterTab(0, 2, false)).toBe(1);
    expect(focusAfterTab(1, 2, false)).toBe(0);
    expect(focusAfterTab(0, 2, true)).toBe(1);
    expect(focusAfterTab(1, 2, true)).toBe(0);
    expect(focusAfterTab(-1, 2, false)).toBe(0);
  });
});
