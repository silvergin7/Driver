export function actionButtonClass(): string {
  return "min-h-11 rounded-md bg-brand px-3 py-2 text-on-brand disabled:border disabled:border-line disabled:bg-disabled-bg disabled:text-ink-muted";
}

export function fitActionButtonClass(): string {
  return `w-fit ${actionButtonClass()}`;
}

export function inputClass(): string {
  return "min-h-11 rounded-md border border-line bg-background px-3 py-2 text-ink";
}

export function choiceButtonClass(pressed: boolean): string {
  if (pressed) {
    return actionButtonClass();
  }
  return "min-h-11 rounded-md border border-line bg-background px-3 py-2 text-ink disabled:border disabled:border-line disabled:bg-disabled-bg disabled:text-ink-muted";
}

export function sectionClass(): string {
  return "flex w-full flex-col gap-3 rounded-xl bg-surface p-4 text-left";
}

export function headingClass(): string {
  return "text-2xl font-semibold text-ink";
}
