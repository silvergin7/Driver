export type OwnerCardView = "hidden" | "switch" | "controls";

export function ownerCardView(input: {
  connected: boolean;
  onAnvil: boolean;
  ownsAny: boolean;
}): OwnerCardView {
  if (!input.connected || !input.ownsAny) {
    return "hidden";
  }
  if (!input.onAnvil) {
    return "switch";
  }
  return "controls";
}
