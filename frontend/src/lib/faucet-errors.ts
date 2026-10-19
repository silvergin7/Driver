import type { Abi } from "viem";
import { driverFaucetAbi } from "../generated/contracts";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
  walletRejectedMessage,
} from "./action-errors";

export const claimFailedMessage = "The claim failed.";
export const claimRevertedMessage = "The claim transaction reverted.";
export { walletRejectedMessage };

const faucetAbi = driverFaucetAbi as Abi;

export function faucetErrorMessage(error: unknown): string {
  return actionErrorMessage(error, [faucetAbi], claimFailedMessage);
}

export function receiptErrorMessage(error: unknown): string {
  return actionReceiptErrorMessage(error, [faucetAbi], claimRevertedMessage);
}
