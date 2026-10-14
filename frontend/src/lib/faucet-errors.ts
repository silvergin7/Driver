import {
  BaseError,
  ContractFunctionRevertedError,
  decodeErrorResult,
  isHex,
  UserRejectedRequestError,
  type Hex,
} from "viem";
import { driverFaucetAbi } from "../generated/contracts";

const faucetErrorMessages = {
  DriverFaucet__ClaimTooSoon: "You can claim again when the cooldown ends.",
  DriverFaucet__DailyLimitReached: "Today's claim limit is full.",
  DriverFaucet__InsufficientBalance:
    "The faucet does not have enough DVR for a claim.",
  DriverFaucet__ZeroAddress: "The faucet token address is missing.",
  DriverFaucet__ZeroValue: "The faucet claim settings are invalid.",
} as const;

export const claimFailedMessage = "The claim failed.";
export const claimRevertedMessage = "The claim transaction reverted.";
export const walletRejectedMessage = "The wallet rejected the transaction.";

type FaucetErrorName = keyof typeof faucetErrorMessages;

function isFaucetErrorName(name: string): name is FaucetErrorName {
  return Object.hasOwn(faucetErrorMessages, name);
}

function knownFaucetMessage(errorName: string): string | undefined {
  if (!isFaucetErrorName(errorName)) {
    return undefined;
  }
  return faucetErrorMessages[errorName];
}

function rawRevertData(error: unknown): Hex | undefined {
  const seen = new Set<unknown>();
  let current: unknown = error;
  while (typeof current === "object" && current !== null && !seen.has(current)) {
    seen.add(current);
    if (
      "data" in current &&
      typeof current.data === "string" &&
      isHex(current.data)
    ) {
      return current.data;
    }
    current = "cause" in current ? current.cause : undefined;
  }
  return undefined;
}

export function faucetErrorMessage(error: unknown): string {
  if (!(error instanceof BaseError)) {
    return claimFailedMessage;
  }
  if (error.walk((cause) => cause instanceof UserRejectedRequestError)) {
    return walletRejectedMessage;
  }
  const reverted = error.walk(
    (cause) => cause instanceof ContractFunctionRevertedError,
  );
  if (
    reverted instanceof ContractFunctionRevertedError &&
    reverted.data?.errorName
  ) {
    return knownFaucetMessage(reverted.data.errorName) ?? claimFailedMessage;
  }
  return claimFailedMessage;
}

export function receiptErrorMessage(error: unknown): string {
  const data = rawRevertData(error);
  if (data === undefined) {
    return claimRevertedMessage;
  }
  try {
    const decoded = decodeErrorResult({
      abi: driverFaucetAbi,
      data,
    });
    return knownFaucetMessage(decoded.errorName) ?? claimRevertedMessage;
  } catch {
    return claimRevertedMessage;
  }
}
