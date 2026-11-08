import { loopSteps, loopTitle } from "@/lib/guide";

export function GuideLoop() {
  return (
    <section className="flex flex-col gap-4" aria-labelledby="loop-title">
      <h2 id="loop-title" className="text-2xl font-semibold text-ink">
        {loopTitle}
      </h2>
      <ol className="flex list-none flex-wrap items-center gap-2">
        {loopSteps.map((step, index) => (
          <li key={step.word} className="flex items-center gap-2">
            <div className="rounded-xl border-2 border-sign bg-background px-3 py-2 text-center shadow-raise">
              <p className="font-semibold text-ink">{step.word}</p>
              <p className="text-sm text-ink-muted">{step.hint}</p>
            </div>
            {index < loopSteps.length - 1 ? (
              <span aria-hidden="true" className="text-ink-muted">
                →
              </span>
            ) : null}
          </li>
        ))}
      </ol>
    </section>
  );
}
