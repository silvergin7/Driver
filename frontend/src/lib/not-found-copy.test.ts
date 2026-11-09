import { describe, expect, it } from "vitest";
import { notFoundCopy } from "./not-found-copy";

describe("notFoundCopy", () => {
  it("uses the wrong-turn wording", () => {
    expect(notFoundCopy).toEqual({
      title: "Wrong turn",
      text: "This road is not on the map.",
      home: "Drive home",
      simulation: "How it works",
    });
  });
});
