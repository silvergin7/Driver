import { createContext, runInContext } from "node:vm";
import { describe, expect, it } from "vitest";
import { resolveTheme, themeChoiceLabel, themeScript } from "./theme";

function runThemeScript(saved: string | null, prefersLight: boolean): string {
  let theme = "";
  const context = createContext({
    localStorage: {
      getItem: () => saved,
    },
    window: {
      matchMedia: () => ({ matches: prefersLight }),
    },
    document: {
      documentElement: {
        setAttribute: (_name: string, value: string) => {
          theme = value;
        },
      },
    },
  });
  runInContext(themeScript, context);
  return theme;
}

describe("resolveTheme", () => {
  it("lets a saved choice win", () => {
    expect(resolveTheme("dark", true)).toBe("dark");
    expect(resolveTheme("light", false)).toBe("light");
  });

  it("ignores an invalid saved value", () => {
    expect(resolveTheme("blue", true)).toBe("light");
    expect(resolveTheme("blue", false)).toBe("dark");
    expect(resolveTheme("", true)).toBe("light");
  });

  it("follows the system when nothing is saved", () => {
    expect(resolveTheme(null, true)).toBe("light");
    expect(resolveTheme(null, false)).toBe("dark");
  });
});

describe("themeChoiceLabel", () => {
  it("names the other theme", () => {
    expect(themeChoiceLabel("dark")).toBe("Use light theme");
    expect(themeChoiceLabel("light")).toBe("Use dark theme");
  });
});

describe("themeScript", () => {
  it("sets the same theme as resolveTheme", () => {
    const cases: Array<[string | null, boolean]> = [
      ["dark", true],
      ["light", false],
      ["nope", true],
      ["", false],
      [null, true],
      [null, false],
    ];
    for (const [saved, prefersLight] of cases) {
      expect(runThemeScript(saved, prefersLight)).toBe(resolveTheme(saved, prefersLight));
    }
  });
});
