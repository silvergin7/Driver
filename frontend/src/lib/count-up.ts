export function countUpFrames(final: string, count: number): readonly string[] {
  if (count <= 1) {
    return [final];
  }
  const match = /^([\d,]+(?:\.\d+)?)(.*)$/.exec(final);
  if (match === null) {
    return Array.from({ length: count - 1 }, () => final).concat(final);
  }
  const numeric = match[1] ?? "";
  const suffix = match[2] ?? "";
  const fraction = numeric.split(".")[1] ?? "";
  const decimals = fraction.length;
  const scale = 10 ** decimals;
  const targetUnits = Math.round(Number(numeric.replaceAll(",", "")) * scale);
  const frames: string[] = [];
  for (let step = 1; step < count; step += 1) {
    const units = Math.floor((targetUnits * step) / count);
    frames.push(`${formatCounted(units, decimals)}${suffix}`);
  }
  frames.push(final);
  return frames;
}

function formatCounted(units: number, decimals: number): string {
  const scale = 10 ** decimals;
  const whole = Math.trunc(units / scale);
  const grouped = String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  if (decimals === 0) {
    return grouped;
  }
  const fraction = String(Math.abs(units % scale)).padStart(decimals, "0");
  return `${grouped}.${fraction}`;
}

export function countUpPlan(input: {
  previous: string | undefined;
  next: string;
  reducedMotion: boolean;
}): { animate: boolean; frames: readonly string[] } {
  if (input.previous !== undefined || input.reducedMotion) {
    return { animate: false, frames: [input.next] };
  }
  return { animate: true, frames: countUpFrames(input.next, 8) };
}
