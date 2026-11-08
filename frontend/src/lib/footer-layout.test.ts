import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

describe("phone footer", () => {
  it("follows the content below 640px and fills the rest of the screen", () => {
    const layout = readFileSync(resolve(process.cwd(), "src/app/layout.tsx"), "utf8");
    const footer = readFileSync(resolve(process.cwd(), "src/components/site-footer.tsx"), "utf8");
    expect(layout).toContain('className="flex flex-none flex-col sm:flex-1"');
    expect(footer).toContain(
      'className="flex-1 border-t border-line bg-surface sm:mt-auto sm:flex-none"',
    );
  });
});
