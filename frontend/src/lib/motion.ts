export const wheelSpinMs = 600;
export const logoBobMs = 600;
export const logoBobPx = 2;
export const logoRevMs = 450;
export const logoRollPx = 6;
export const driveMs = 600;
export const parkHoldMs = 400;
export const parkFadeMs = 200;

export const logoRevKeyframes = [
  { offset: 0, x: 0, rotate: 0 },
  { offset: 0.15, x: -1, rotate: -3 },
  { offset: 0.3, x: 1, rotate: 3 },
  { offset: 0.45, x: -1, rotate: -2 },
  { offset: 0.6, x: 0, rotate: 0 },
  { offset: 1, x: logoRollPx, rotate: 0 },
] as const;

export function motionAllowed(reduced: boolean): boolean {
  return !reduced;
}

export function parkOffsets(
  drive: number,
  hold: number,
  fade: number,
): { totalMs: number; moveEnd: number; fadeStart: number } {
  const totalMs = drive + hold + fade;
  return {
    totalMs,
    moveEnd: drive / totalMs,
    fadeStart: (drive + hold) / totalMs,
  };
}

export function logoRevFrames(): Array<{ offset: number; transform: string }> {
  return logoRevKeyframes.map((frame) => ({
    offset: frame.offset,
    transform: `translateX(${frame.x}px) rotate(${frame.rotate}deg)`,
  }));
}
