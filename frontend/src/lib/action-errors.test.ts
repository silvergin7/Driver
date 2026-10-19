import { describe, expect, it } from "vitest";
import {
  CallExecutionError,
  ContractFunctionExecutionError,
  ContractFunctionRevertedError,
  encodeErrorResult,
  ExecutionRevertedError,
  RpcRequestError,
  type Abi,
  type Hex,
} from "viem";
import { driverFaucetAbi, mockUsdcFaucetAbi } from "../generated/contracts";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "./action-errors";
import { claimFailedMessage, claimRevertedMessage } from "./faucet-errors";

const faucetAbi = driverFaucetAbi as Abi;
const usdcFaucetAbi = mockUsdcFaucetAbi as Abi;

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

describe("actionErrorMessage", () => {
  it("maps MockUsdcFaucet__ClaimTooSoon from the second ABI", () => {
    const data = encodeErrorResult({
      abi: usdcFaucetAbi,
      errorName: "MockUsdcFaucet__ClaimTooSoon",
      args: [50n],
    });
    const reverted = new ContractFunctionRevertedError({
      abi: usdcFaucetAbi,
      data,
      functionName: "claim",
    });
    const error = new ContractFunctionExecutionError(reverted, {
      abi: usdcFaucetAbi,
      functionName: "claim",
    });
    expect(
      actionErrorMessage(
        error,
        [faucetAbi, usdcFaucetAbi],
        claimFailedMessage,
      ),
    ).toBe("You can claim again when the cooldown ends.");
  });

  it("maps MockUsdcFaucet__DailyLimitReached", () => {
    const data = encodeErrorResult({
      abi: usdcFaucetAbi,
      errorName: "MockUsdcFaucet__DailyLimitReached",
      args: [86_400n],
    });
    const reverted = new ContractFunctionRevertedError({
      abi: usdcFaucetAbi,
      data,
      functionName: "claim",
    });
    expect(
      actionErrorMessage(
        new ContractFunctionExecutionError(reverted, {
          abi: usdcFaucetAbi,
          functionName: "claim",
        }),
        [usdcFaucetAbi],
        claimFailedMessage,
      ),
    ).toBe("Today's claim limit is full.");
  });
});

describe("actionReceiptErrorMessage", () => {
  it("decodes a faucet error when the fund ABI does not match", () => {
    const data = encodeErrorResult({
      abi: faucetAbi,
      errorName: "DriverFaucet__InsufficientBalance",
      args: [0n, 10n],
    });
    expect(
      actionReceiptErrorMessage(
        replayRevert(data),
        [usdcFaucetAbi, faucetAbi],
        claimRevertedMessage,
      ),
    ).toBe("The faucet does not have enough DVR for a claim.");
  });
});
