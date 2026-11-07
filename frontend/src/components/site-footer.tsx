import { chainName } from "@/config/contracts";
import { footerNotice } from "@/lib/network-copy";

export function SiteFooter() {
  return (
    <footer className="mt-auto border-t border-line bg-surface">
      <p className="mx-auto max-w-5xl px-6 py-6 text-sm text-ink">
        Driver (DVR). {footerNotice(chainName)}
      </p>
    </footer>
  );
}
