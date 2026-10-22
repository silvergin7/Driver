import { getAddress, type Address } from "viem";

export type OwnerActionTargetInput =
  | {
      kind: "harvest";
      contractName: "CruiseControl" | "DegenDriver";
      address: Address;
    }
  | {
      kind: "advanceTime";
      contractName: "DemoDriverClock";
      address: Address;
      seconds: bigint;
    };

export type OwnerActionTarget = {
  text: string;
  lead: string;
  shortAddress: string;
  address: Address;
};

export function ownerActionTarget(
  action: OwnerActionTargetInput,
): OwnerActionTarget {
  const address = getAddress(action.address);
  const shortAddress = `${address.slice(0, 6)}…${address.slice(-4)}`;
  const call =
    action.kind === "harvest"
      ? "harvest(minDvrOut)"
      : `advanceTime(${action.seconds})`;
  const lead = `Calls ${call} on ${action.contractName} `;
  return {
    text: `${lead}${shortAddress}`,
    lead,
    shortAddress,
    address,
  };
}
