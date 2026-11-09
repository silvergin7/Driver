import { ClaimTokens } from "@/components/claim-tokens";
import { ClaimUsdc } from "@/components/claim-usdc";

export function FaucetsCard() {
  return (
    <div className="grid gap-6 sm:grid-cols-2 sm:items-stretch">
      <ClaimTokens />
      <ClaimUsdc />
    </div>
  );
}
