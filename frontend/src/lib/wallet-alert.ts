export function walletAlertText(
  connectError: string | undefined,
  switchError: string | undefined,
  connected: boolean,
  onAnvil: boolean,
): string | undefined {
  if (connectError !== undefined && !connected) {
    return connectError;
  }
  if (switchError !== undefined && connected && !onAnvil) {
    return switchError;
  }
  return undefined;
}
