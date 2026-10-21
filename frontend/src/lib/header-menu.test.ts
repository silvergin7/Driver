import { describe, expect, it } from "vitest";
import { nextHeaderMenu } from "./header-menu";

describe("nextHeaderMenu", () => {
  it("opens the nav from closed", () => {
    expect(nextHeaderMenu("closed", "toggle-nav")).toBe("nav");
  });

  it("closes an open nav", () => {
    expect(nextHeaderMenu("nav", "toggle-nav")).toBe("closed");
  });

  it("opens the account menu from closed", () => {
    expect(nextHeaderMenu("closed", "toggle-account")).toBe("account");
  });

  it("closes an open account menu", () => {
    expect(nextHeaderMenu("account", "toggle-account")).toBe("closed");
  });

  it("opening the account menu closes the nav", () => {
    expect(nextHeaderMenu("nav", "toggle-account")).toBe("account");
  });

  it("opening the nav closes the account menu", () => {
    expect(nextHeaderMenu("account", "toggle-nav")).toBe("nav");
  });

  it("close shuts the nav", () => {
    expect(nextHeaderMenu("nav", "close")).toBe("closed");
  });

  it("close shuts the account menu", () => {
    expect(nextHeaderMenu("account", "close")).toBe("closed");
  });

  it("close stays closed", () => {
    expect(nextHeaderMenu("closed", "close")).toBe("closed");
  });
});
