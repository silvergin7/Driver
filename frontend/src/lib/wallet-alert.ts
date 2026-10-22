export function walletAlertText(
  connectError: string | undefined,
  switchError: string | undefined,
  connected: boolean,
  onChain: boolean,
): string | undefined {
  if (connectError !== undefined && !connected) {
    return connectError;
  }
  if (switchError !== undefined && connected && !onChain) {
    return switchError;
  }
  return undefined;
}
