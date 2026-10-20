"use client";

import { useSyncExternalStore } from "react";
import {
  darkTheme,
  lightTheme,
  themeChoiceLabel,
  themeStorageKey,
  type ThemeName,
} from "@/lib/theme";

function subscribe(onStoreChange: () => void) {
  const media = window.matchMedia("(prefers-color-scheme: light)");
  const observer = new MutationObserver(onStoreChange);
  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-theme"],
  });
  media.addEventListener("change", onStoreChange);
  return () => {
    observer.disconnect();
    media.removeEventListener("change", onStoreChange);
  };
}

function currentTheme(): ThemeName {
  return document.documentElement.getAttribute("data-theme") === lightTheme
    ? lightTheme
    : darkTheme;
}

function ThemeIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-6 w-6 text-ink">
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeWidth="2" />
      <path d="M12 3a9 9 0 0 0 0 18Z" fill="currentColor" />
    </svg>
  );
}

export function ThemeSwitch() {
  const theme = useSyncExternalStore(subscribe, currentTheme, () => undefined);

  if (theme === undefined) {
    return null;
  }

  const next: ThemeName = theme === darkTheme ? lightTheme : darkTheme;
  const label = themeChoiceLabel(theme);

  function choose() {
    localStorage.setItem(themeStorageKey, next);
    document.documentElement.setAttribute("data-theme", next);
  }

  return (
    <button
      type="button"
      className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-ink hover:bg-surface"
      aria-label={label}
      title={label}
      onClick={choose}
    >
      <ThemeIcon />
    </button>
  );
}
