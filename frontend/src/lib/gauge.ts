const rest = -120;
const sweep = 240;

export function gaugeAngle(value: bigint, max: bigint): number {
  if (max <= 0n || value <= 0n) {
    return rest;
  }
  if (value >= max) {
    return rest + sweep;
  }
  return rest + (sweep * Number(value)) / Number(max);
}

export function needleMotion(input: {
  seen: boolean;
  reducedMotion: boolean;
}): "sweep" | "jump" {
  if (input.seen || input.reducedMotion) {
    return "jump";
  }
  return "sweep";
}
