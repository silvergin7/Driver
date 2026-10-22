import { describe, expect, it } from "vitest";
import { ownerCardView } from "./owner-card";

describe("ownerCardView", () => {
  it("hides the card when disconnected", () => {
    expect(
      ownerCardView({ connected: false, onChain: false, ownsAny: false }),
    ).toBe("hidden");
    expect(
      ownerCardView({ connected: false, onChain: false, ownsAny: true }),
    ).toBe("hidden");
    expect(
      ownerCardView({ connected: false, onChain: true, ownsAny: false }),
    ).toBe("hidden");
    expect(
      ownerCardView({ connected: false, onChain: true, ownsAny: true }),
    ).toBe("hidden");
  });

  it("hides the card off the selected chain for a non-owner", () => {
    expect(
      ownerCardView({ connected: true, onChain: false, ownsAny: false }),
    ).toBe("hidden");
  });

  it("asks an owner off the selected chain to switch", () => {
    expect(
      ownerCardView({ connected: true, onChain: false, ownsAny: true }),
    ).toBe("switch");
  });

  it("hides the card on the selected chain for a non-owner", () => {
    expect(
      ownerCardView({ connected: true, onChain: true, ownsAny: false }),
    ).toBe("hidden");
  });

  it("shows the controls to an owner on the selected chain", () => {
    expect(
      ownerCardView({ connected: true, onChain: true, ownsAny: true }),
    ).toBe("controls");
  });
});
