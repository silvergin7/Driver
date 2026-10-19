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
import { choiceButtonClass } from "@/lib/control-class";
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
      <div className="mx-auto flex h-16 max-w-5xl items-center gap-4 px-6">
        <LogoMark linked />
        <nav aria-label="Pages" className="hidden items-center gap-4 md:flex">
          {navItems.map((item) => (
            <PageLink key={item.href} href={item.href} label={item.label} />
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <button
            ref={menuButton}
            type="button"
            className={`${choiceButtonClass(false)} md:hidden`}
            aria-expanded={open}
            aria-controls="site-menu"
            onClick={() => setOpenPath(open ? undefined : pathname)}
          >
            Menu
          </button>
          <ConnectWallet compact showAlert={false} controls={controls} />
        </div>
      </div>
      {open ? (
        <nav
          ref={menu}
          id="site-menu"
          aria-label="Pages"
          className="flex flex-col gap-3 bg-background px-6 py-4 md:hidden"
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
      <WalletBarAlert message={controls.alertMessage} />
    </header>
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
