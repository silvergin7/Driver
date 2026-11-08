export type Box = {
  left: number;
  top: number;
  width: number;
  height: number;
};

export const driveCar = { width: 28, height: 16 } as const;
export const driveLaneInset = 2;

export type RevClick = {
  reducedMotion: boolean;
  altKey: boolean;
  ctrlKey: boolean;
  metaKey: boolean;
  shiftKey: boolean;
  button: number;
};

export type DriveClick = RevClick & {
  currentPage: boolean;
  fromMenu: boolean;
};

export function shouldRev(click: RevClick): boolean {
  if (click.reducedMotion) {
    return false;
  }
  if (click.altKey || click.ctrlKey || click.metaKey || click.shiftKey) {
    return false;
  }
  if (click.button !== 0) {
    return false;
  }
  return true;
}

export function shouldDrive(click: DriveClick): boolean {
  if (click.reducedMotion || click.currentPage || click.fromMenu) {
    return false;
  }
  if (click.altKey || click.ctrlKey || click.metaKey || click.shiftKey) {
    return false;
  }
  if (click.button !== 0) {
    return false;
  }
  return true;
}

export function driveEnds(
  row: Box,
  logo: Box,
  link: Box,
  car: { width: number; height: number } = driveCar,
): { startX: number; startY: number; endX: number; endY: number } {
  const startX = logo.left - row.left + logo.width / 2 - car.width / 2;
  const startY = logo.top - row.top + logo.height / 2 - car.height / 2;
  const rawEndX = link.left - row.left + link.width / 2 - car.width / 2;
  const maxX = Math.max(0, row.width - car.width);
  const endX = Math.min(maxX, Math.max(0, rawEndX));
  const endY = row.height - car.height - driveLaneInset;
  return { startX, startY, endX, endY };
}
