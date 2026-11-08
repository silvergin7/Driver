import { describe, expect, it } from "vitest";
import { glossary, loopSteps, pictureSteps } from "./guide";
import { stepIndexAfter } from "./simulation";

describe("guide copy", () => {
  it("gives every loop step a word and a hint", () => {
    expect(loopSteps).toHaveLength(9);
    for (const step of loopSteps) {
      expect(step.word.length).toBeGreaterThan(0);
      expect(step.hint.length).toBeGreaterThan(0);
    }
  });

  it("gives every picture a title, caption and alt text", () => {
    expect(pictureSteps).toHaveLength(6);
    for (const step of pictureSteps) {
      expect(step.title.length).toBeGreaterThan(0);
      expect(step.caption.length).toBeGreaterThan(0);
      expect(step.alt.length).toBeGreaterThan(0);
    }
  });

  it("gives every glossary term a definition", () => {
    expect(glossary.length).toBeGreaterThan(0);
    for (const entry of glossary) {
      expect(entry.term.length).toBeGreaterThan(0);
      expect(entry.definition.length).toBeGreaterThan(0);
    }
  });

  it("keeps the picture guide inside its steps", () => {
    const count = pictureSteps.length;
    expect(stepIndexAfter(0, count, "back")).toBe(0);
    expect(stepIndexAfter(0, count, "next")).toBe(1);
    expect(stepIndexAfter(count - 1, count, "next")).toBe(count - 1);
    expect(stepIndexAfter(2, count, "back")).toBe(1);
  });
});
