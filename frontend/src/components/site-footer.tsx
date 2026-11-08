import { chainName } from "@/config/contracts";
import { footerNotice } from "@/lib/network-copy";

export function SiteFooter() {
  return (
    <footer className="flex-1 border-t border-line bg-surface sm:mt-auto sm:flex-none">
      <p className="mx-auto max-w-5xl px-6 py-6 text-sm text-ink">
        {footerNotice(chainName)}
      </p>
    </footer>
  );
}
