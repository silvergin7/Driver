import { getAddress, zeroAddress } from "viem";
import { describe, expect, it } from "vitest";
import { roundChoice } from "./round-choice";

const highway = "0x4ed7c70f96b99c776995fb64377f0d4ab3b0e1c1";

describe("roundChoice", () => {
  it("uses the leader as the round's choice", () => {
    expect(roundChoice(highway)).toBe(getAddress(highway));
  });

  it("has no choice when the leader is the zero address", () => {
    expect(roundChoice(zeroAddress)).toBeUndefined();
  });
});
