export type HeaderMenu = "closed" | "nav" | "account";

export type HeaderMenuAction = "toggle-nav" | "toggle-account" | "close";

export function nextHeaderMenu(current: HeaderMenu, action: HeaderMenuAction): HeaderMenu {
  if (action === "close") {
    return "closed";
  }
  if (action === "toggle-nav") {
    return current === "nav" ? "closed" : "nav";
  }
  return current === "account" ? "closed" : "account";
}
