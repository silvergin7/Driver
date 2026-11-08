import { glossary } from "./guide";

export const glossaryPlaceholder = "Pick a word…";

export const glossaryHint = "Pick a word to see what it means.";

export function glossaryOptions(): readonly string[] {
  return [glossaryPlaceholder, ...glossary.map((entry) => entry.term)];
}

export function glossaryChoice(
  term: string,
): { term: string; definition: string } | null {
  return glossary.find((entry) => entry.term === term) ?? null;
}
