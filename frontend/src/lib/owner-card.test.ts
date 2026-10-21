import { describe, expect, it } from "vitest";
import { ownerCardView } from "./owner-card";

describe("ownerCardView", () => {
  it("hides the card when disconnected", () => {
    expect(
      ownerCardView({ connected: false, onAnvil: false, ownsAny: false }),
    ).toBe("hidden");
    expect(
      ownerCardView({ connected: false, onAnvil: false, ownsAny: true }),
    ).toBe("hidden");
    expect(
      ownerCardView({ connected: false, onAnvil: true, ownsAny: false }),
    ).toBe("hidden");
    expect(
      ownerCardView({ connected: false, onAnvil: true, ownsAny: true }),
    ).toBe("hidden");
  });

  it("hides the card off Anvil for a non-owner", () => {
    expect(
      ownerCardView({ connected: true, onAnvil: false, ownsAny: false }),
    ).toBe("hidden");
  });

  it("asks an owner off Anvil to switch", () => {
    expect(
      ownerCardView({ connected: true, onAnvil: false, ownsAny: true }),
    ).toBe("switch");
  });

  it("hides the card on Anvil for a non-owner", () => {
    expect(
      ownerCardView({ connected: true, onAnvil: true, ownsAny: false }),
    ).toBe("hidden");
  });

  it("shows the controls to an owner on Anvil", () => {
    expect(
      ownerCardView({ connected: true, onAnvil: true, ownsAny: true }),
    ).toBe("controls");
  });
});
