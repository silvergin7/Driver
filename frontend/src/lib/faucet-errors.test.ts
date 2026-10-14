import { describe, expect, it } from "vitest";
import {
  CallExecutionError,
  ContractFunctionExecutionError,
  ContractFunctionRevertedError,
  encodeErrorResult,
  ExecutionRevertedError,
  RpcRequestError,
  UserRejectedRequestError,
  type Hex,
} from "viem";
import { driverFaucetAbi } from "../generated/contracts";
import {
  claimFailedMessage,
  claimRevertedMessage,
  faucetErrorMessage,
  receiptErrorMessage,
  walletRejectedMessage,
} from "./faucet-errors";

const zeroAddress = "0x0000000000000000000000000000000000000000";

function claimRevert(
  data: ReturnType<typeof encodeErrorResult>,
): ContractFunctionExecutionError {
  const reverted = new ContractFunctionRevertedError({
    abi: driverFaucetAbi,
    data,
    functionName: "claim",
  });
  return new ContractFunctionExecutionError(reverted, {
    abi: driverFaucetAbi,
    functionName: "claim",
  });
}

function replayRevert(data: Hex): CallExecutionError {
  return new CallExecutionError(
    new ExecutionRevertedError({
      cause: new RpcRequestError({
        body: {},
        url: "http://127.0.0.1:8545",
        error: { code: 3, message: "execution reverted", data },
      }),
    }),
    {},
  );
}

describe("faucetErrorMessage", () => {
  it("maps DriverFaucet__ClaimTooSoon", () => {
    expect(
      faucetErrorMessage(
        claimRevert(
          encodeErrorResult({
            abi: driverFaucetAbi,
            errorName: "DriverFaucet__ClaimTooSoon",
            args: [50n],
          }),
        ),
      ),
    ).toBe("You can claim again when the cooldown ends.");
  });

  it("maps DriverFaucet__DailyLimitReached", () => {
    expect(
      faucetErrorMessage(
        claimRevert(
          encodeErrorResult({
            abi: driverFaucetAbi,
            errorName: "DriverFaucet__DailyLimitReached",
            args: [86_400n],
          }),
        ),
      ),
    ).toBe("Today's claim limit is full.");
  });

  it("maps DriverFaucet__InsufficientBalance", () => {
    expect(
      faucetErrorMessage(
        claimRevert(
          encodeErrorResult({
            abi: driverFaucetAbi,
            errorName: "DriverFaucet__InsufficientBalance",
            args: [0n, 10n],
          }),
        ),
      ),
    ).toBe("The faucet does not have enough DVR for a claim.");
  });

  it("maps DriverFaucet__ZeroAddress", () => {
    expect(
      faucetErrorMessage(
        claimRevert(
          encodeErrorResult({
            abi: driverFaucetAbi,
            errorName: "DriverFaucet__ZeroAddress",
          }),
        ),
      ),
    ).toBe("The faucet token address is missing.");
  });

  it("maps DriverFaucet__ZeroValue", () => {
    expect(
      faucetErrorMessage(
        claimRevert(
          encodeErrorResult({
            abi: driverFaucetAbi,
            errorName: "DriverFaucet__ZeroValue",
          }),
        ),
      ),
    ).toBe("The faucet claim settings are invalid.");
  });

  it("maps a user-rejected request", () => {
    expect(
      faucetErrorMessage(new UserRejectedRequestError(new Error("rejected"))),
    ).toBe(walletRejectedMessage);
  });

  it("maps an unknown error to the generic claim failure", () => {
    expect(
      faucetErrorMessage(
        claimRevert(
          encodeErrorResult({
            abi: driverFaucetAbi,
            errorName: "SafeERC20FailedOperation",
            args: [zeroAddress],
          }),
        ),
      ),
    ).toBe(claimFailedMessage);
  });
});

describe("receiptErrorMessage", () => {
  it("maps an unknown reason to the reverted claim message", () => {
    expect(receiptErrorMessage(new Error("unknown reason"))).toBe(
      claimRevertedMessage,
    );
  });

  it("maps encoded DriverFaucet__ClaimTooSoon from a replayed call", () => {
    expect(
      receiptErrorMessage(
        replayRevert(
          encodeErrorResult({
            abi: driverFaucetAbi,
            errorName: "DriverFaucet__ClaimTooSoon",
            args: [50n],
          }),
        ),
      ),
    ).toBe("You can claim again when the cooldown ends.");
  });

  it("maps an unmapped revert to the reverted claim message", () => {
    expect(
      receiptErrorMessage(
        replayRevert(
          encodeErrorResult({
            abi: driverFaucetAbi,
            errorName: "SafeERC20FailedOperation",
            args: [zeroAddress],
          }),
        ),
      ),
    ).toBe(claimRevertedMessage);
  });
});
