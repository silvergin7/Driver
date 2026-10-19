import { describe, expect, it } from "vitest";
import { isCurrentPage, navItems } from "./nav";

describe("navItems", () => {
  it("lists the four routes in order", () => {
    expect(navItems.map((item) => item.href)).toEqual([
      "/",
      "/game",
      "/token",
      "/community",
    ]);
    expect(navItems.map((item) => item.label)).toEqual([
      "Home",
      "Game",
      "Token",
      "Community",
    ]);
  });
});

describe("isCurrentPage", () => {
  it("matches the home page only to itself", () => {
    expect(isCurrentPage("/", "/")).toBe(true);
    expect(isCurrentPage("/game", "/")).toBe(false);
    expect(isCurrentPage("/token", "/")).toBe(false);
    expect(isCurrentPage("/community", "/")).toBe(false);
  });

  it("matches each other page only to its own path", () => {
    expect(isCurrentPage("/game", "/game")).toBe(true);
    expect(isCurrentPage("/game/extra", "/game")).toBe(false);
    expect(isCurrentPage("/", "/game")).toBe(false);
    expect(isCurrentPage("/token", "/token")).toBe(true);
    expect(isCurrentPage("/community", "/community")).toBe(true);
  });
});
