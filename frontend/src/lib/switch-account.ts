import { walletFailedMessage } from "./wallet-errors";

export const switchAccountUnsupportedMessage = "Switch accounts in your wallet.";

export function switchAccountError(error: unknown): string | undefined {
  const code = errorCode(error);
  if (code === 4001) {
    return undefined;
  }
  if (code === -32601 || code === 4200) {
    return switchAccountUnsupportedMessage;
  }
  return walletFailedMessage;
}

function errorCode(error: unknown): number | undefined {
  const seen = new Set<unknown>();
  let current: unknown = error;
  while (typeof current === "object" && current !== null && !seen.has(current)) {
    seen.add(current);
    if ("code" in current && typeof current.code === "number") {
      return current.code;
    }
    current = "cause" in current ? current.cause : undefined;
  }
  return undefined;
}
