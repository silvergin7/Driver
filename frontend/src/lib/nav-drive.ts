export type RevClick = {
  reducedMotion: boolean;
  altKey: boolean;
  ctrlKey: boolean;
  metaKey: boolean;
  shiftKey: boolean;
  button: number;
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
