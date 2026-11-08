"use client";

import { useEffect, useRef } from "react";
import { CarMark } from "@/components/logo-mark";
import { driveMs, parkFadeMs, parkHoldMs, parkOffsets } from "@/lib/motion";

export function NavCar({
  startX,
  startY,
  endX,
  endY,
  onDone,
}: {
  startX: number;
  startY: number;
  endX: number;
  endY: number;
  onDone: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const done = useRef(onDone);

  useEffect(() => {
    done.current = onDone;
  }, [onDone]);

  useEffect(() => {
    const car = ref.current;
    if (car === null) {
      return;
    }
    const offsets = parkOffsets(driveMs, parkHoldMs, parkFadeMs);
    const animation = car.animate(
      [
        {
          transform: `translate(${startX}px, ${startY}px)`,
          opacity: 1,
          easing: "ease-in-out",
        },
        {
          transform: `translate(${endX}px, ${endY}px)`,
          opacity: 1,
          offset: offsets.moveEnd,
        },
        {
          transform: `translate(${endX}px, ${endY}px)`,
          opacity: 1,
          offset: offsets.fadeStart,
        },
        {
          transform: `translate(${endX}px, ${endY}px)`,
          opacity: 0,
        },
      ],
      { duration: offsets.totalMs, fill: "forwards" },
    );
    animation.onfinish = () => {
      done.current();
    };
    return () => {
      animation.cancel();
    };
  }, [startX, startY, endX, endY]);

  return (
    <div ref={ref} aria-hidden="true" className="pointer-events-none absolute top-0 left-0 h-4 w-7">
      <CarMark spin />
    </div>
  );
}
