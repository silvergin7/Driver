export const themeStorageKey = "theme";
export const darkTheme = "dark";
export const lightTheme = "light";

export type ThemeName = typeof darkTheme | typeof lightTheme;

export function resolveTheme(saved: string | null, prefersLight: boolean): ThemeName {
  if (saved === darkTheme || saved === lightTheme) {
    return saved;
  }
  return prefersLight ? lightTheme : darkTheme;
}

export function themeChoiceLabel(theme: ThemeName): string {
  return theme === darkTheme ? "Use light theme" : "Use dark theme";
}

export const themeScript = `(function(){try{var saved=localStorage.getItem(${JSON.stringify(themeStorageKey)});var prefersLight=window.matchMedia("(prefers-color-scheme: light)").matches;var theme=saved===${JSON.stringify(darkTheme)}||saved===${JSON.stringify(lightTheme)}?saved:(prefersLight?${JSON.stringify(lightTheme)}:${JSON.stringify(darkTheme)});document.documentElement.setAttribute("data-theme",theme);}catch(e){}})();`;
