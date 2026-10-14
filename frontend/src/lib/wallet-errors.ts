import { ProviderNotFoundError } from "wagmi";
import { UserRejectedRequestError } from "viem";

export const walletMissingMessage = "No browser wallet was found.";
export const connectionRejectedMessage = "The wallet rejected the connection.";
export const switchRejectedMessage = "The wallet rejected the network switch.";
export const walletFailedMessage = "The wallet request failed.";

export type WalletAction = "connect" | "switch";

function causedBy(
  error: unknown,
  type: typeof ProviderNotFoundError | typeof UserRejectedRequestError,
): boolean {
  const seen = new Set<unknown>();
  let current: unknown = error;
  while (typeof current === "object" && current !== null && !seen.has(current)) {
    seen.add(current);
    if (current instanceof type) {
      return true;
    }
    current = "cause" in current ? current.cause : undefined;
  }
  return false;
}

export function walletErrorMessage(
  error: unknown,
  action: WalletAction,
): string {
  if (causedBy(error, ProviderNotFoundError)) {
    return walletMissingMessage;
  }
  if (causedBy(error, UserRejectedRequestError)) {
    return action === "switch"
      ? switchRejectedMessage
      : connectionRejectedMessage;
  }
  return walletFailedMessage;
}
