export function assertVercelChain(
  vercel: string | undefined,
  chain: string | undefined,
): void {
  if (vercel === "1" && chain !== "sepolia") {
    throw new Error(
      'A Vercel build must set NEXT_PUBLIC_CHAIN to "sepolia".',
    );
  }
}
