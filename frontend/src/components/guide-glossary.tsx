"use client";

import { useState } from "react";
import { glossary, glossaryTitle } from "@/lib/guide";
import {
  glossaryChoice,
  glossaryHint,
  glossaryPlaceholder,
} from "@/lib/glossary-choice";
import { inputClass, sectionClass } from "@/lib/control-class";

export function GuideGlossary() {
  const [term, setTerm] = useState("");
  const chosen = glossaryChoice(term);

  return (
    <section className="flex flex-col gap-4" aria-labelledby="glossary-title">
      <h2 id="glossary-title" className="text-2xl font-semibold text-ink">
        {glossaryTitle}
      </h2>
      <div className="flex flex-col gap-2">
        <label htmlFor="glossary-word" className="font-semibold text-ink">
          Choose a word
        </label>
        <select
          id="glossary-word"
          className={`${inputClass()} w-full`}
          value={term}
          onChange={(event) => setTerm(event.target.value)}
        >
          <option value="">{glossaryPlaceholder}</option>
          {glossary.map((entry) => (
            <option key={entry.term} value={entry.term}>
              {entry.term}
            </option>
          ))}
        </select>
      </div>
      <div aria-live="polite" className={sectionClass()}>
        {chosen === null ? (
          <p className="text-ink">{glossaryHint}</p>
        ) : (
          <>
            <h3 className="text-sm font-semibold text-ink">{chosen.term}</h3>
            <p className="text-ink">{chosen.definition}</p>
          </>
        )}
      </div>
    </section>
  );
}
