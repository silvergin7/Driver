export function switchPrompt(chainLabel: string, detail?: string): string {
  if (detail === undefined) {
    return `Switch to ${chainLabel}`;
  }
  return `Switch to ${chainLabel} ${detail}`;
}
