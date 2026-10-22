import { afterEach, describe, expect, it, vi } from "vitest";
import { assertVercelChain } from "./vercel-chain";

const guardMessage =
  'A Vercel build must set NEXT_PUBLIC_CHAIN to "sepolia".';

function message(run: () => void): string {
  try {
    run();
  } catch (error) {
    if (error instanceof Error) {
      return error.message;
    }
    throw error;
  }
  throw new Error("expected a throw");
}

const quietVercel = [undefined, "", "0"] as const;
const quietChain = [undefined, "", "anvil", "sepolia"] as const;

describe("assertVercelChain", () => {
  it.each(
    quietVercel.flatMap((vercel) =>
      quietChain.map((chain) => [vercel, chain] as const),
    ),
  )("allows vercel %j and chain %j", (vercel, chain) => {
    expect(() => assertVercelChain(vercel, chain)).not.toThrow();
  });

  it("allows a Vercel build that selects Sepolia", () => {
    expect(() => assertVercelChain("1", "sepolia")).not.toThrow();
  });

  it.each([undefined, "", "anvil", "SEPOLIA", "sepolia ", " anvil"])(
    "stops a Vercel build when the chain is %j",
    (chain) => {
      expect(message(() => assertVercelChain("1", chain))).toBe(guardMessage);
    },
  );
});

describe("next config guard", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.resetModules();
  });

  it("stops a Vercel build when the chain is unset", async () => {
    vi.resetModules();
    vi.stubEnv("VERCEL", "1");
    vi.stubEnv("NEXT_PUBLIC_CHAIN", undefined);
    await expect(import("../../next.config.ts")).rejects.toThrow(guardMessage);
  });

  it("loads the config for a Sepolia Vercel build", async () => {
    vi.resetModules();
    vi.stubEnv("VERCEL", "1");
    vi.stubEnv("NEXT_PUBLIC_CHAIN", "sepolia");
    const loaded = await import("../../next.config.ts");
    expect(loaded.default.devIndicators).toBe(false);
  });

  it("loads the config when Vercel is unset", async () => {
    vi.resetModules();
    vi.stubEnv("VERCEL", undefined);
    vi.stubEnv("NEXT_PUBLIC_CHAIN", undefined);
    const loaded = await import("../../next.config.ts");
    expect(loaded.default.devIndicators).toBe(false);
  });
});
