export const navItems = [
  { href: "/", label: "Home" },
  { href: "/game", label: "Game" },
  { href: "/faucet", label: "Faucet" },
  { href: "/swap", label: "Swap" },
  { href: "/token", label: "Token" },
  { href: "/community", label: "Community" },
] as const;

export function isCurrentPage(pathname: string, href: string): boolean {
  if (href === "/") {
    return pathname === "/";
  }
  return pathname === href;
}
