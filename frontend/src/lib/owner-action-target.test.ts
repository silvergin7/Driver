import type { Address } from "viem";
import { foundry, sepolia } from "viem/chains";
import { describe, expect, it } from "vitest";
import addresses from "../config/addresses.json" with { type: "json" };
import { addressExplorer } from "./explorer";
import { ownerActionTarget } from "./owner-action-target";

const book = addresses as Record<string, Record<string, string>>;

function raw(chainId: string, name: string): Address {
  return book[chainId][name] as Address;
}

describe("ownerActionTarget", () => {
  it("names the Anvil harvest and skip calls", () => {
    expect(
      ownerActionTarget({
        kind: "harvest",
        contractName: "CruiseControl",
        address: raw("31337", "CruiseControl"),
      }).text,
    ).toBe("Calls harvest(minDvrOut) on CruiseControl 0x1613…78E8");
    expect(
      ownerActionTarget({
        kind: "harvest",
        contractName: "DegenDriver",
        address: raw("31337", "DegenDriver"),
      }).text,
    ).toBe("Calls harvest(minDvrOut) on DegenDriver 0x8513…891C");
    expect(
      ownerActionTarget({
        kind: "advanceTime",
        contractName: "DemoDriverClock",
        address: raw("31337", "DemoDriverClock"),
        seconds: 2_592_000n,
      }).text,
    ).toBe("Calls advanceTime(2592000) on DemoDriverClock 0x9A67…7508");
  });

  it("names the Sepolia harvest and skip calls", () => {
    const cruise = ownerActionTarget({
      kind: "harvest",
      contractName: "CruiseControl",
      address: raw("11155111", "CruiseControl"),
    });
    const degen = ownerActionTarget({
      kind: "harvest",
      contractName: "DegenDriver",
      address: raw("11155111", "DegenDriver"),
    });
    const clock = ownerActionTarget({
      kind: "advanceTime",
      contractName: "DemoDriverClock",
      address: raw("11155111", "DemoDriverClock"),
      seconds: 2_592_000n,
    });
    expect(cruise.text).toBe(
      "Calls harvest(minDvrOut) on CruiseControl 0xD3D1…e93a",
    );
    expect(degen.text).toBe(
      "Calls harvest(minDvrOut) on DegenDriver 0x2dD0…a374",
    );
    expect(clock.text).toBe(
      "Calls advanceTime(2592000) on DemoDriverClock 0x6D5c…85Aa",
    );
    expect(cruise.text).toBe(`${cruise.lead}${cruise.shortAddress}`);
    expect(addressExplorer(sepolia, cruise.address)).toEqual({
      kind: "link",
      href: "https://sepolia.etherscan.io/address/0xD3D13fba75D43235a6595e891555bD22Abf1e93a",
      name: "Etherscan",
    });
    expect(addressExplorer(foundry, cruise.address)).toEqual({ kind: "local" });
  });

  it("prints the epoch the skip will send", () => {
    expect(
      ownerActionTarget({
        kind: "advanceTime",
        contractName: "DemoDriverClock",
        address: raw("11155111", "DemoDriverClock"),
        seconds: 1n,
      }).text,
    ).toBe("Calls advanceTime(1) on DemoDriverClock 0x6D5c…85Aa");
  });
});
