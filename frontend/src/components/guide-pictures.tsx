"use client";

import { useState, type KeyboardEvent } from "react";
import { guideImageSrc, pictureSteps, pictureTitle } from "@/lib/guide";
import { fitActionButtonClass } from "@/lib/control-class";
import { stepIndexAfter } from "@/lib/simulation";

export function GuidePictures() {
  const [index, setIndex] = useState(0);
  const step = pictureSteps[index];
  if (step === undefined) {
    return null;
  }

  function move(action: "back" | "next") {
    setIndex((current) => stepIndexAfter(current, pictureSteps.length, action));
  }

  function onKey(event: KeyboardEvent<HTMLElement>) {
    if (event.key === "ArrowRight") {
      event.preventDefault();
      move("next");
    }
    if (event.key === "ArrowLeft") {
      event.preventDefault();
      move("back");
    }
  }

  return (
    <section
      className="flex flex-col gap-4"
      aria-roledescription="carousel"
      aria-labelledby="picture-title"
      onKeyDown={onKey}
    >
      <h2 id="picture-title" className="text-2xl font-semibold text-ink">
        {pictureTitle}
      </h2>
      <figure className="flex flex-col gap-3" aria-live="polite">
        <div className="relative aspect-[4/3] overflow-hidden rounded-xl">
          <GuideShot id={step.id} theme="day" alt={step.alt} className="dark:hidden" />
          <GuideShot id={step.id} theme="night" alt={step.alt} className="hidden dark:block" />
        </div>
        <figcaption className="flex flex-col gap-1">
          <p className="text-sm text-ink-muted">
            {index + 1} of {pictureSteps.length}
          </p>
          <h3 className="text-xl font-semibold text-ink">{step.title}</h3>
          <p className="text-ink">{step.caption}</p>
        </figcaption>
      </figure>
      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          className={fitActionButtonClass()}
          disabled={index === 0}
          onClick={() => move("back")}
        >
          Back
        </button>
        <button
          type="button"
          className={fitActionButtonClass()}
          disabled={index === pictureSteps.length - 1}
          onClick={() => move("next")}
        >
          Next
        </button>
        <div className="flex">
          {pictureSteps.map((item, itemIndex) => (
            <button
              key={item.id}
              type="button"
              className="inline-flex h-11 w-11 items-center justify-center"
              aria-label={item.title}
              aria-current={itemIndex === index ? "step" : undefined}
              onClick={() => setIndex(itemIndex)}
            >
              <span
                aria-hidden="true"
                className={
                  itemIndex === index
                    ? "h-2 w-2 rounded-full bg-brand"
                    : "h-2 w-2 rounded-full bg-line"
                }
              />
            </button>
          ))}
        </div>
      </div>
    </section>
  );
}

function GuideShot({
  id,
  theme,
  alt,
  className,
}: {
  id: string;
  theme: "day" | "night";
  alt: string;
  className: string;
}) {
  const narrow = guideImageSrc(id, theme, 768);
  const wide = guideImageSrc(id, theme, 1440);
  return (
    // eslint-disable-next-line @next/next/no-img-element -- shipped day and night sizes
    <img
      src={narrow}
      srcSet={`${narrow} 768w, ${wide} 1440w`}
      sizes="(min-width: 768px) 48rem, 100vw"
      alt={alt}
      className={`absolute inset-0 h-full w-full object-cover ${className}`}
    />
  );
}
