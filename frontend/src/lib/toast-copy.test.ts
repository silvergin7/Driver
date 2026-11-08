import { describe, expect, it } from "vitest";
import { walletRejectedMessage } from "./action-errors";
import { toastCopy } from "./toast-copy";

const rejected = walletRejectedMessage;

describe("toastCopy", () => {
  it("uses the confirmed sentence", () => {
    expect(
      toastCopy({ outcome: "confirmed", confirmed: "Claimed 10 DVR.", error: rejected }),
    ).toBe("Claimed 10 DVR.");
    expect(
      toastCopy({ outcome: "confirmed", confirmed: "Bought DVR.", error: rejected }),
    ).toBe("Bought DVR.");
    expect(
      toastCopy({ outcome: "confirmed", confirmed: "Approved.", error: rejected }),
    ).toBe("Approved.");
    expect(
      toastCopy({ outcome: "confirmed", confirmed: "Locked 10 DVR.", error: rejected }),
    ).toBe("Locked 10 DVR.");
    expect(
      toastCopy({ outcome: "confirmed", confirmed: "Harvested Fund 1.", error: rejected }),
    ).toBe("Harvested Fund 1.");
  });

  it("passes the card's error sentence through", () => {
    expect(
      toastCopy({
        outcome: "failed",
        confirmed: "Bought DVR.",
        error: rejected,
      }),
    ).toBe(rejected);
    expect(
      toastCopy({
        outcome: "failed",
        confirmed: "Claimed 100 mUSDC.",
        error: "You can claim again when the cooldown ends.",
      }),
    ).toBe("You can claim again when the cooldown ends.");
  });
});
