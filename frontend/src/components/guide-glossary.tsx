import { glossary, glossaryTitle } from "@/lib/guide";

export function GuideGlossary() {
  return (
    <section className="flex flex-col gap-4" aria-labelledby="glossary-title">
      <h2 id="glossary-title" className="text-2xl font-semibold text-ink">
        {glossaryTitle}
      </h2>
      <dl className="flex flex-col gap-4">
        {glossary.map((entry) => (
          <div key={entry.term} className="flex flex-col gap-1">
            <dt className="font-semibold text-ink">{entry.term}</dt>
            <dd className="text-ink">{entry.definition}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
