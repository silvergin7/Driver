import { ClaimTokens } from "@/components/claim-tokens";
import { ClaimUsdc } from "@/components/claim-usdc";
import { Card } from "@/components/ui/card";

export function FaucetsCard() {
  return (
    <Card title="Faucets">
      <div className="grid gap-6 sm:grid-cols-2 sm:items-stretch">
        <ClaimTokens />
        <ClaimUsdc />
      </div>
    </Card>
  );
}
