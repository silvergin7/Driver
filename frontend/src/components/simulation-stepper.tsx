"use client";

import { useState, type ReactNode } from "react";
import { Card } from "@/components/ui/card";
import { StatList } from "@/components/ui/stat-list";
import {
  choiceButtonClass,
  fitActionButtonClass,
} from "@/lib/control-class";
import {
  findRun,
  lockChoices,
  stepCopy,
  stepIndexAfter,
  stepRows,
  swapChoices,
  voteChoices,
  type LockChoice,
  type SwapChoice,
  type VoteChoice,
} from "@/lib/simulation";

export function SimulationStepper() {
  const [swap, setSwap] = useState<SwapChoice>("25");
  const [lock, setLock] = useState<LockChoice>("half");
  const [vote, setVote] = useState<VoteChoice>("highway");
  const [index, setIndex] = useState(0);
  const run = findRun(swap, lock, vote);
  const copy = stepCopy[index];
  const rows = stepRows(run.steps, index);

  function chooseSwap(next: SwapChoice) {
    setSwap(next);
    setIndex(0);
  }

  function chooseLock(next: LockChoice) {
    setLock(next);
    setIndex(0);
  }

  function chooseVote(next: VoteChoice) {
    setVote(next);
    setIndex(0);
  }

  return (
    <Card title={copy?.title ?? "Simulation"} subtitle={`Step ${index + 1} of ${stepCopy.length}`}>
      <p className="text-ink">{copy?.text}</p>
      {index === 0 ? (
        <div className="flex flex-col gap-4">
          <ChoiceRow label="Swap">
            {swapChoices.map((choice) => (
              <button
                key={choice.id}
                type="button"
                className={choiceButtonClass(swap === choice.id)}
                aria-pressed={swap === choice.id}
                onClick={() => chooseSwap(choice.id)}
              >
                {choice.label}
              </button>
            ))}
          </ChoiceRow>
          <ChoiceRow label="Lock">
            {lockChoices.map((choice) => (
              <button
                key={choice.id}
                type="button"
                className={choiceButtonClass(lock === choice.id)}
                aria-pressed={lock === choice.id}
                onClick={() => chooseLock(choice.id)}
              >
                {choice.label}
              </button>
            ))}
          </ChoiceRow>
          <ChoiceRow label="Vote">
            {voteChoices.map((choice) => (
              <button
                key={choice.id}
                type="button"
                className={choiceButtonClass(vote === choice.id)}
                aria-pressed={vote === choice.id}
                onClick={() => chooseVote(choice.id)}
              >
                {choice.label}
              </button>
            ))}
          </ChoiceRow>
        </div>
      ) : (
        <p className="text-sm text-ink-muted">
          {swapChoices.find((choice) => choice.id === swap)?.label}, lock{" "}
          {lock}, vote {voteChoices.find((choice) => choice.id === vote)?.label}.
        </p>
      )}
      <div aria-live="polite">
        <StatList rows={rows} />
      </div>
      <div className="flex flex-wrap gap-3">
        <button
          type="button"
          className={fitActionButtonClass()}
          disabled={index === 0}
          onClick={() => setIndex((current) => stepIndexAfter(current, run.steps.length, "back"))}
        >
          Back
        </button>
        <button
          type="button"
          className={fitActionButtonClass()}
          disabled={index === run.steps.length - 1}
          onClick={() => setIndex((current) => stepIndexAfter(current, run.steps.length, "next"))}
        >
          Next
        </button>
        <button
          type="button"
          className={fitActionButtonClass()}
          onClick={() => setIndex(0)}
        >
          Start over
        </button>
      </div>
    </Card>
  );
}

function ChoiceRow({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm text-ink-muted">{label}</p>
      <div className="flex flex-wrap gap-2">{children}</div>
    </div>
  );
}
