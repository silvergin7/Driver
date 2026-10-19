import {
  BaseError,
  ContractFunctionRevertedError,
  decodeErrorResult,
  isHex,
  UserRejectedRequestError,
  type Abi,
  type Hex,
} from "viem";

export const walletRejectedMessage = "The wallet rejected the transaction.";

export const actionErrorMessages = {
  DriverFaucet__ClaimTooSoon: "You can claim again when the cooldown ends.",
  DriverFaucet__DailyLimitReached: "Today's claim limit is full.",
  DriverFaucet__InsufficientBalance:
    "The faucet does not have enough DVR for a claim.",
  DriverFaucet__ZeroAddress: "The faucet token address is missing.",
  DriverFaucet__ZeroValue: "The faucet claim settings are invalid.",
  MockUsdcFaucet__ClaimTooSoon: "You can claim again when the cooldown ends.",
  MockUsdcFaucet__DailyLimitReached: "Today's claim limit is full.",
  MockUsdcFaucet__ZeroAddress: "The faucet token address is missing.",
  MockUsdcFaucet__ZeroValue: "The faucet claim settings are invalid.",
  DriverVote__Voted: "Unlock waits until this round ends.",
  DriverVote__NothingLocked: "Lock DVR before voting.",
  DriverVote__InsufficientLock: "That is more DVR than the lock.",
  DriverVote__StrategyNotAllowed: "That farm is not listed.",
  DriverVote__ZeroAmount: "Enter an amount above zero.",
  ERC20InsufficientAllowance: "The wallet has not approved enough tokens.",
  ERC20InsufficientBalance: "The wallet does not hold enough tokens.",
} as const;

type ErrorName = keyof typeof actionErrorMessages;

function knownMessage(errorName: string): string | undefined {
  if (!Object.hasOwn(actionErrorMessages, errorName)) {
    return undefined;
  }
  return actionErrorMessages[errorName as ErrorName];
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

function messageFromData(
  data: Hex,
  abis: readonly Abi[],
): string | undefined {
  for (const abi of abis) {
    try {
      const decoded = decodeErrorResult({ abi, data });
      return knownMessage(decoded.errorName);
    } catch {
      continue;
    }
  }
  return undefined;
}

export function actionErrorMessage(
  error: unknown,
  abis: readonly Abi[],
  failedMessage: string,
): string {
  if (!(error instanceof BaseError)) {
    return failedMessage;
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
    const message = knownMessage(reverted.data.errorName);
    if (message !== undefined) {
      return message;
    }
  }
  const data = rawRevertData(error);
  if (data !== undefined) {
    const message = messageFromData(data, abis);
    if (message !== undefined) {
      return message;
    }
  }
  return failedMessage;
}

export function actionReceiptErrorMessage(
  error: unknown,
  abis: readonly Abi[],
  revertedMessage: string,
): string {
  const data = rawRevertData(error);
  if (data === undefined) {
    return revertedMessage;
  }
  return messageFromData(data, abis) ?? revertedMessage;
}
