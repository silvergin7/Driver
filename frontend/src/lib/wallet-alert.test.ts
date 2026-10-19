import { describe, expect, it } from "vitest";
import { walletAlertText } from "./wallet-alert";

describe("walletAlertText", () => {
  it("shows a connect error only while disconnected", () => {
    expect(walletAlertText("No browser wallet was found.", undefined, false, false)).toBe(
      "No browser wallet was found.",
    );
    expect(walletAlertText("No browser wallet was found.", undefined, true, false)).toBeUndefined();
  });

  it("shows a switch error only on the wrong network", () => {
    expect(walletAlertText(undefined, "The wallet rejected the network switch.", true, false)).toBe(
      "The wallet rejected the network switch.",
    );
    expect(walletAlertText(undefined, "The wallet rejected the network switch.", true, true)).toBeUndefined();
    expect(walletAlertText(undefined, "The wallet rejected the network switch.", false, false)).toBeUndefined();
  });

  it("prefers the connect error while disconnected", () => {
    expect(walletAlertText("connect", "switch", false, false)).toBe("connect");
  });
});
