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
import {
  driverFaucetAbi,
  driverTokenAbi,
  driverVoteAbi,
  mockUsdcFaucetAbi,
} from "../generated/contracts";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "./action-errors";
import { claimFailedMessage, claimRevertedMessage } from "./faucet-errors";

const faucetAbi = driverFaucetAbi as Abi;
const usdcFaucetAbi = mockUsdcFaucetAbi as Abi;
const voteAbi = driverVoteAbi as Abi;
const tokenAbi = driverTokenAbi as Abi;

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

describe("actionErrorMessage vote", () => {
  it("maps DriverVote__StrategyNotAllowed", () => {
    const data = encodeErrorResult({
      abi: voteAbi,
      errorName: "DriverVote__StrategyNotAllowed",
      args: [zeroAddress],
    });
    expect(
      actionErrorMessage(
        executionError(voteAbi, data),
        [voteAbi, tokenAbi],
        "The transaction failed.",
      ),
    ).toBe("That farm is not listed.");
  });

  it("maps DriverVote__ZeroAmount", () => {
    const data = encodeErrorResult({
      abi: voteAbi,
      errorName: "DriverVote__ZeroAmount",
    });
    expect(
      actionErrorMessage(
        executionError(voteAbi, data),
        [voteAbi],
        "The transaction failed.",
      ),
    ).toBe("Enter an amount above zero.");
  });

  it("maps ERC20InsufficientBalance from the token ABI", () => {
    const data = encodeErrorResult({
      abi: tokenAbi,
      errorName: "ERC20InsufficientBalance",
      args: [zeroAddress, 0n, 1n],
    });
    expect(
      actionReceiptErrorMessage(
        replayRevert(data),
        [voteAbi, tokenAbi],
        "The transaction reverted.",
      ),
    ).toBe("The wallet does not hold enough tokens.");
  });
});

const zeroAddress = "0x0000000000000000000000000000000000000000";

function executionError(abi: Abi, data: Hex): ContractFunctionExecutionError {
  const reverted = new ContractFunctionRevertedError({
    abi,
    data,
    functionName: "vote",
  });
  return new ContractFunctionExecutionError(reverted, {
    abi,
    args: [zeroAddress],
    functionName: "vote",
  });
}

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
