"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import {
  ConnectWallet,
  WalletBarAlert,
  useWalletControls,
} from "@/components/connect-wallet";
import { LogoMark } from "@/components/logo-mark";
import { ThemeSwitch } from "@/components/theme-switch";
import { isCurrentPage, navItems } from "@/lib/nav";

export function SiteHeader() {
  const controls = useWalletControls();
  const pathname = usePathname();
  const [openPath, setOpenPath] = useState<string | undefined>(undefined);
  const open = openPath === pathname;
  const menuButton = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLElement>(null);

  useEffect(() => {
    if (!open) {
      return;
    }
    const first = menu.current?.querySelector("a");
    if (first instanceof HTMLAnchorElement) {
      first.focus();
    }
    function onKey(event: KeyboardEvent) {
      if (event.key !== "Escape") {
        return;
      }
      setOpenPath(undefined);
      menuButton.current?.focus();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <header className="sticky top-0 z-50 border-b border-line bg-background">
      <div className="mx-auto flex h-16 max-w-5xl items-center gap-4 px-4 md:px-6">
        <LogoMark />
        <nav aria-label="Pages" className="hidden items-center gap-4 lg:flex">
          {navItems.map((item) => (
            <PageLink key={item.href} href={item.href} label={item.label} />
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <ThemeSwitch />
          <button
            ref={menuButton}
            type="button"
            className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-ink hover:bg-surface lg:hidden"
            aria-label="Menu"
            aria-expanded={open}
            aria-controls="site-menu"
            onClick={() => setOpenPath(open ? undefined : pathname)}
          >
            <MenuIcon />
          </button>
          <ConnectWallet compact showAlert={false} controls={controls} />
        </div>
      </div>
      {open ? (
        <nav
          ref={menu}
          id="site-menu"
          aria-label="Pages"
          className="flex flex-col gap-3 bg-background px-4 py-4 lg:hidden"
        >
          {navItems.map((item) => (
            <PageLink
              key={item.href}
              href={item.href}
              label={item.label}
              onNavigate={() => setOpenPath(undefined)}
            />
          ))}
        </nav>
      ) : null}
      <WalletBarAlert message={controls.accountAlert ?? controls.alertMessage} />
    </header>
  );
}

function MenuIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-6 w-6">
      <path
        d="M4 7h16M4 12h16M4 17h16"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  );
}

function PageLink({
  href,
  label,
  onNavigate,
}: {
  href: string;
  label: string;
  onNavigate?: () => void;
}) {
  const pathname = usePathname();
  const current = isCurrentPage(pathname, href);
  return (
    <Link
      href={href}
      aria-current={current ? "page" : undefined}
      onClick={onNavigate}
      className={
        current
          ? "inline-flex min-h-11 items-center text-sign underline"
          : "inline-flex min-h-11 items-center text-ink"
      }
    >
      {label}
    </Link>
  );
}
