export const soundStorageKey = "driver-sound";
export const soundOnValue = "on";
export const soundOffValue = "off";

export function soundEnabledFromStorage(read: () => string | null): boolean {
  try {
    return read() === soundOnValue;
  } catch {
    return false;
  }
}

export function persistSoundEnabled(
  enabled: boolean,
  write: (value: string) => void,
): boolean {
  try {
    write(enabled ? soundOnValue : soundOffValue);
    return true;
  } catch {
    return false;
  }
}
