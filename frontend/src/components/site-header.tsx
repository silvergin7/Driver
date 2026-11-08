"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState, type MouseEvent } from "react";
import {
  ConnectWallet,
  WalletBarAlert,
  useWalletControls,
} from "@/components/connect-wallet";
import { LogoMark } from "@/components/logo-mark";
import { NavCar } from "@/components/nav-car";
import { ThemeSwitch } from "@/components/theme-switch";
import { nextHeaderMenu, type HeaderMenu } from "@/lib/header-menu";
import { motionAllowed } from "@/lib/motion";
import { isCurrentPage, navItems } from "@/lib/nav";
import { driveEnds, shouldDrive, type Box } from "@/lib/nav-drive";

export function SiteHeader() {
  const controls = useWalletControls();
  const pathname = usePathname();
  const [menu, setMenu] = useState<HeaderMenu>("closed");
  const [menuPath, setMenuPath] = useState(pathname);
  if (pathname !== menuPath) {
    setMenuPath(pathname);
    setMenu("closed");
  }
  if (!controls.connection.isConnected && menu === "account") {
    setMenu("closed");
  }
  const navOpen = menu === "nav";
  const menuButton = useRef<HTMLButtonElement>(null);
  const navMenu = useRef<HTMLElement>(null);
  const barRef = useRef<HTMLDivElement>(null);
  const destination = useRef<string | null>(null);
  const tripCount = useRef(0);
  const [trip, setTrip] = useState<{
    id: number;
    startX: number;
    startY: number;
    endX: number;
    endY: number;
  } | null>(null);

  function clearTrip() {
    destination.current = null;
    setTrip(null);
  }

  function driveTo(event: MouseEvent<HTMLAnchorElement>, href: string) {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (
      !shouldDrive({
        reducedMotion: !motionAllowed(reduced),
        currentPage: isCurrentPage(pathname, href),
        fromMenu: false,
        altKey: event.altKey,
        ctrlKey: event.ctrlKey,
        metaKey: event.metaKey,
        shiftKey: event.shiftKey,
        button: event.button,
      })
    ) {
      return;
    }
    const row = barRef.current;
    const logo = row?.querySelector(".logo-mark");
    if (row === null || !(logo instanceof HTMLElement)) {
      return;
    }
    destination.current = href;
    tripCount.current += 1;
    const ends = driveEnds(
      toBox(row.getBoundingClientRect()),
      toBox(logo.getBoundingClientRect()),
      toBox(event.currentTarget.getBoundingClientRect()),
    );
    setTrip({ id: tripCount.current, ...ends });
  }

  useEffect(() => {
    if (!navOpen) {
      return;
    }
    const first = navMenu.current?.querySelector("a");
    if (first instanceof HTMLAnchorElement) {
      first.focus();
    }
    function onKey(event: KeyboardEvent) {
      if (event.key !== "Escape") {
        return;
      }
      setMenu("closed");
      menuButton.current?.focus();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [navOpen]);

  useEffect(() => {
    if (destination.current === null || pathname === destination.current) {
      return;
    }
    destination.current = null;
    setTrip(null);
  }, [pathname]);

  useEffect(() => {
    function clear() {
      if (destination.current === null) {
        return;
      }
      destination.current = null;
      setTrip(null);
    }
    function onMedia() {
      const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      const desktop = window.matchMedia("(min-width: 1024px)").matches;
      if (reduced || !desktop) {
        clear();
      }
    }
    const reducedMedia = window.matchMedia("(prefers-reduced-motion: reduce)");
    const desktopMedia = window.matchMedia("(min-width: 1024px)");
    window.addEventListener("resize", clear);
    window.addEventListener("popstate", clear);
    reducedMedia.addEventListener("change", onMedia);
    desktopMedia.addEventListener("change", onMedia);
    return () => {
      window.removeEventListener("resize", clear);
      window.removeEventListener("popstate", clear);
      reducedMedia.removeEventListener("change", onMedia);
      desktopMedia.removeEventListener("change", onMedia);
    };
  }, []);

  return (
    <header className="sticky top-0 z-50 border-b border-line bg-background">
      <div
        ref={barRef}
        className="relative mx-auto flex h-16 max-w-5xl items-center gap-1 px-4 sm:gap-4 md:px-6"
      >
        {trip !== null ? (
          <NavCar
            key={trip.id}
            startX={trip.startX}
            startY={trip.startY}
            endX={trip.endX}
            endY={trip.endY}
            onDone={clearTrip}
          />
        ) : null}
        <LogoMark />
        <nav aria-label="Pages" className="hidden items-center gap-4 lg:flex">
          {navItems.map((item) => (
            <PageLink
              key={item.href}
              href={item.href}
              label={item.label}
              onActivate={(event) => driveTo(event, item.href)}
            />
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <ThemeSwitch />
          <button
            ref={menuButton}
            type="button"
            className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-ink hover:bg-surface lg:hidden"
            aria-label="Menu"
            aria-expanded={navOpen}
            aria-controls="site-menu"
            onClick={() => setMenu((current) => nextHeaderMenu(current, "toggle-nav"))}
          >
            <MenuIcon />
          </button>
          <ConnectWallet
            compact
            showAlert={false}
            controls={controls}
            accountMenu={{
              open: menu === "account",
              onToggle: () => setMenu((current) => nextHeaderMenu(current, "toggle-account")),
              onClose: () => setMenu("closed"),
            }}
          />
        </div>
      </div>
      {navOpen ? (
        <nav
          ref={navMenu}
          id="site-menu"
          aria-label="Pages"
          className="flex flex-col gap-3 bg-background px-4 py-4 lg:hidden"
        >
          {navItems.map((item) => (
            <PageLink
              key={item.href}
              href={item.href}
              label={item.label}
              onNavigate={() => setMenu("closed")}
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

function toBox(rect: DOMRect): Box {
  return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
}

function PageLink({
  href,
  label,
  onNavigate,
  onActivate,
}: {
  href: string;
  label: string;
  onNavigate?: () => void;
  onActivate?: (event: MouseEvent<HTMLAnchorElement>) => void;
}) {
  const pathname = usePathname();
  const current = isCurrentPage(pathname, href);
  return (
    <Link
      href={href}
      aria-current={current ? "page" : undefined}
      onClick={(event) => {
        onActivate?.(event);
        onNavigate?.();
      }}
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
