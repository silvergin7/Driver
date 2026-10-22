export type OwnerCardView = "hidden" | "switch" | "controls";

export function ownerCardView(input: {
  connected: boolean;
  onChain: boolean;
  ownsAny: boolean;
}): OwnerCardView {
  if (!input.connected || !input.ownsAny) {
    return "hidden";
  }
  if (!input.onChain) {
    return "switch";
  }
  return "controls";
}
