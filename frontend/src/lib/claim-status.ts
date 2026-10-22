import type { ClaimEligibility } from "./claim-eligibility";
import { switchPrompt } from "./switch-prompt";

export type ClaimStatusInput = {
  chainLabel: string;
  claimed: string | undefined;
  confirming: boolean;
  connected: boolean;
  eligibility: ClaimEligibility["status"] | undefined;
  onChain: boolean;
  readsFailed: boolean;
  readsReady: boolean;
  simulating: boolean;
  writePending: boolean;
};

export function claimStatus(input: ClaimStatusInput): string | undefined {
  if (!input.connected) {
    return "Connect a wallet to claim.";
  }
  if (!input.onChain) {
    return switchPrompt(input.chainLabel, "to claim.");
  }
  if (input.readsFailed) {
    return "Claim status unavailable.";
  }
  if (!input.readsReady) {
    return "Loading claim status…";
  }
  if (input.simulating) {
    return "Checking the claim.";
  }
  if (input.writePending) {
    return "Waiting for the wallet.";
  }
  if (input.confirming) {
    return "Confirming the claim.";
  }
  if (input.claimed) {
    return input.claimed;
  }
  if (input.eligibility === "allowed") {
    return "Ready to claim.";
  }
  return undefined;
}
