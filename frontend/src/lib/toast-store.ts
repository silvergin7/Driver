export type ToastNotice = {
  id: number;
  message: string;
  sound: boolean;
};

let current: ToastNotice | undefined;
let nextId = 0;
const listeners = new Set<() => void>();

function emit(): void {
  for (const listener of listeners) {
    listener();
  }
}

export function publishToast(message: string, sound: boolean): void {
  nextId += 1;
  current = { id: nextId, message, sound };
  emit();
}

export function dismissToast(id: number): void {
  if (current?.id !== id) {
    return;
  }
  current = undefined;
  emit();
}

export function subscribeToast(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function toastSnapshot(): ToastNotice | undefined {
  return current;
}
