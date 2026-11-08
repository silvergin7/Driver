export function toastCopy(input: {
  outcome: "confirmed" | "failed";
  confirmed: string;
  error: string;
}): string {
  if (input.outcome === "failed") {
    return input.error;
  }
  return input.confirmed;
}
