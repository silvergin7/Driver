import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  driveMs,
  logoBobMs,
  logoBobPx,
  logoRevFrames,
  logoRevKeyframes,
  logoRevMs,
  logoRollPx,
  motionAllowed,
  parkFadeMs,
  parkHoldMs,
  parkOffsets,
  wheelSpinMs,
} from "./motion";

describe("motionAllowed", () => {
  it("allows motion when reduced motion is off", () => {
    expect(motionAllowed(false)).toBe(true);
  });

  it("blocks motion when reduced motion is on", () => {
    expect(motionAllowed(true)).toBe(false);
  });
});

describe("parkOffsets", () => {
  it("holds after the drive and then fades", () => {
    expect(parkOffsets(600, 400, 200)).toEqual({
      totalMs: 1200,
      moveEnd: 0.5,
      fadeStart: 5 / 6,
    });
  });
});

describe("motion constants", () => {
  it("locks the durations, the roll, and the rev frames", () => {
    expect(wheelSpinMs).toBe(600);
    expect(logoBobMs).toBe(600);
    expect(logoBobPx).toBe(2);
    expect(logoRevMs).toBe(450);
    expect(logoRollPx).toBe(6);
    expect(driveMs).toBe(600);
    expect(parkHoldMs).toBe(400);
    expect(parkFadeMs).toBe(200);
    expect(logoRevKeyframes).toEqual([
      { offset: 0, x: 0, rotate: 0 },
      { offset: 0.15, x: -1, rotate: -3 },
      { offset: 0.3, x: 1, rotate: 3 },
      { offset: 0.45, x: -1, rotate: -2 },
      { offset: 0.6, x: 0, rotate: 0 },
      { offset: 1, x: 6, rotate: 0 },
    ]);
    expect(logoRevFrames()[5]).toEqual({
      offset: 1,
      transform: "translateX(6px) rotate(0deg)",
    });
  });
});

describe("motion stylesheet", () => {
  const css = readFileSync(resolve(process.cwd(), "src/app/globals.css"), "utf8");

  it("locks the logo animation declarations", () => {
    expect(css).toContain(
      `@media (prefers-reduced-motion: no-preference) {
  @media (hover: hover) {
    .logo-mark:hover .wheel {
      animation: wheel-spin ${wheelSpinMs / 1000}s linear infinite;
    }

    .logo-mark:hover .logo-car {
      animation: logo-bob ${logoBobMs / 1000}s ease-in-out infinite alternate;
    }
  }

  .logo-mark:focus-visible .wheel {
    animation: wheel-spin ${wheelSpinMs / 1000}s linear infinite;
  }

  .logo-mark:focus-visible .logo-car {
    animation: logo-bob ${logoBobMs / 1000}s ease-in-out infinite alternate;
  }

  .wheel.is-spinning {
    animation: wheel-spin ${wheelSpinMs / 1000}s linear infinite;
  }
}`,
    );
    expect(css).toContain(`@keyframes wheel-spin {
  to {
    transform: rotate(360deg);
  }
}`);
    expect(css).toContain(`@keyframes logo-bob {
  to {
    transform: translateY(-${logoBobPx}px);
  }
}`);
    expect(css).toContain(`@media (hover: hover) and (pointer: fine) {
  body {
    cursor: url("/cursor-car.svg") 31 15, auto;
  }

  a[href]:not([aria-disabled="true"]),
  button:not(:disabled):not([aria-disabled="true"]),
  summary:not([aria-disabled="true"]) {
    cursor: pointer;
  }

  input:not(:disabled):not([aria-disabled="true"]):not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="button"]):not([type="submit"]),
  textarea:not(:disabled):not([aria-disabled="true"]) {
    cursor: text;
  }

  select,
  :disabled,
  [aria-disabled="true"] {
    cursor: default;
  }
}`);
    expect(css).not.toContain("scene-pan");
  });
});
