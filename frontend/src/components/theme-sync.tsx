"use client";

import { useEffect } from "react";
import { resolveTheme, themeStorageKey } from "@/lib/theme";

export function ThemeSync() {
  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: light)");
    function apply() {
      const saved = localStorage.getItem(themeStorageKey);
      document.documentElement.setAttribute("data-theme", resolveTheme(saved, media.matches));
    }
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, []);

  return null;
}
