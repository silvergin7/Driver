export const welcomeStorageKey = "driver-welcome";
export const welcomeSeenValue = "seen";

export const welcomeCopy = {
  title: "Welcome to Driver",
  text: "Driver is a learning project on Ethereum mainnet. Its tokens have no real value, but every action here costs real gas. Want to see how it all works first, for free?",
  trySimulation: "Try the simulation",
  enterSite: "Enter the live site",
} as const;

export function welcomeDecision(pathname: string, stored: string | null): boolean {
  if (pathname === "/simulation") {
    return false;
  }
  return stored !== welcomeSeenValue;
}

export function focusAfterTab(current: number, count: number, shift: boolean): number {
  if (count <= 0) {
    return 0;
  }
  if (shift) {
    return current <= 0 ? count - 1 : current - 1;
  }
  return current >= count - 1 ? 0 : current + 1;
}
