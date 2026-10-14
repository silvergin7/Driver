import { describe, expect, it } from "vitest";
import { UserRejectedRequestError } from "viem";
import { ProviderNotFoundError } from "wagmi";
import {
  connectionRejectedMessage,
  switchRejectedMessage,
  walletErrorMessage,
  walletMissingMessage,
} from "./wallet-errors";

function rejectedRequest(): UserRejectedRequestError {
  const cause = new Error("User rejected the request.");
  return new UserRejectedRequestError(Object.assign(cause, { code: 4001 }));
}

describe("walletErrorMessage", () => {
  it("maps a missing injected provider", () => {
    expect(
      walletErrorMessage(new ProviderNotFoundError(), "connect"),
    ).toBe(walletMissingMessage);
  });

  it("maps a rejected connection", () => {
    expect(walletErrorMessage(rejectedRequest(), "connect")).toBe(
      connectionRejectedMessage,
    );
  });

  it("maps a rejected network switch", () => {
    expect(walletErrorMessage(rejectedRequest(), "switch")).toBe(
      switchRejectedMessage,
    );
  });
});
