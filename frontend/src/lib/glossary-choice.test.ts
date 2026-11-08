import { describe, expect, it } from "vitest";
import { glossary } from "./guide";
import {
  glossaryChoice,
  glossaryHint,
  glossaryOptions,
  glossaryPlaceholder,
} from "./glossary-choice";

describe("glossary menu", () => {
  it("lists the placeholder and then the 28 terms", () => {
    expect(glossary).toHaveLength(28);
    expect(glossaryOptions()).toEqual([
      glossaryPlaceholder,
      ...glossary.map((entry) => entry.term),
    ]);
  });

  it("shows the hint before a choice", () => {
    expect(glossaryHint).toBe("Pick a word to see what it means.");
    expect(glossaryChoice("")).toBeNull();
  });

  it("shows the chosen definition and replaces it", () => {
    const first = glossary[0];
    const second = glossary[1];
    expect(first).toBeDefined();
    expect(second).toBeDefined();
    expect(glossaryChoice(first.term)).toEqual(first);
    expect(glossaryChoice(second.term)).toEqual(second);
    expect(first.definition).not.toBe(second.definition);
  });
});
