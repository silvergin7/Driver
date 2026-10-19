"use client";

import { useSyncExternalStore } from "react";
import { choiceButtonClass } from "@/lib/control-class";
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

export function ThemeSwitch({ menu = false }: { menu?: boolean }) {
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

  if (menu) {
    return (
      <button
        type="button"
        className="min-h-11 text-left text-ink md:hidden"
        aria-label={label}
        onClick={choose}
      >
        {label}
      </button>
    );
  }

  return (
    <button
      type="button"
      className={`${choiceButtonClass(false)} hidden md:inline-flex`}
      aria-label={label}
      onClick={choose}
    >
      {label}
    </button>
  );
}
