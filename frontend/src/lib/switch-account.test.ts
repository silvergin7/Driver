import { describe, expect, it } from "vitest";
import {
  switchAccountError,
  switchAccountUnsupportedMessage,
} from "./switch-account";
import { walletFailedMessage } from "./wallet-errors";

describe("switchAccountError", () => {
  it("stays quiet when the user rejects the request", () => {
    expect(switchAccountError({ code: 4001 })).toBeUndefined();
  });

  it("stays quiet when a wrapped error was rejected", () => {
    expect(switchAccountError({ cause: { code: 4001 } })).toBeUndefined();
  });

  it("names a wallet that does not support the method", () => {
    expect(switchAccountError({ code: -32601 })).toBe(switchAccountUnsupportedMessage);
    expect(switchAccountError({ code: 4200 })).toBe(switchAccountUnsupportedMessage);
  });

  it("uses the wallet failure wording for anything else", () => {
    expect(switchAccountError({ code: -32000 })).toBe(walletFailedMessage);
    expect(switchAccountError(new Error("no"))).toBe(walletFailedMessage);
  });
});
