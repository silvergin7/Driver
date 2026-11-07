"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { CarTile } from "@/components/logo-mark";
import { choiceButtonClass, fitActionButtonClass } from "@/lib/control-class";
import {
  focusAfterTab,
  welcomeCopy,
  welcomeDecision,
  welcomeSeenValue,
  welcomeStorageKey,
} from "@/lib/welcome";

export function WelcomeDialog() {
  const pathname = usePathname();
  const router = useRouter();
  const [closed, setClosed] = useState(false);
  const client = useSyncExternalStore(subscribeNothing, () => true, () => false);
  const dialog = useRef<HTMLDivElement>(null);
  const open = client && !closed && welcomeDecision(pathname, readWelcome());

  function dismiss() {
    try {
      localStorage.setItem(welcomeStorageKey, welcomeSeenValue);
    } catch {
      setClosed(true);
      return;
    }
    setClosed(true);
  }

  useEffect(() => {
    if (!open) {
      return;
    }
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const first = dialog.current?.querySelector<HTMLElement>("a, button");
    first?.focus();
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        dismiss();
        return;
      }
      if (event.key !== "Tab" || dialog.current === null) {
        return;
      }
      const items = [...dialog.current.querySelectorAll<HTMLElement>("a, button")];
      if (items.length === 0) {
        return;
      }
      const current = items.indexOf(document.activeElement as HTMLElement);
      const next = focusAfterTab(current, items.length, event.shiftKey);
      event.preventDefault();
      items[next]?.focus();
    }
    window.addEventListener("keydown", onKey, true);
    return () => {
      document.body.style.overflow = previous;
      window.removeEventListener("keydown", onKey, true);
    };
  }, [open]);

  if (!open) {
    return null;
  }

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-background/80 p-4">
      <div
        ref={dialog}
        role="dialog"
        aria-modal="true"
        aria-labelledby="welcome-title"
        aria-describedby="welcome-text"
        className="flex w-full max-w-md flex-col gap-4 rounded-xl bg-surface p-6 text-left shadow-raise"
      >
        <CarTile />
        <h2 id="welcome-title" className="text-2xl font-semibold text-ink">
          {welcomeCopy.title}
        </h2>
        <p id="welcome-text" className="text-ink">
          {welcomeCopy.text}
        </p>
        <div className="flex flex-wrap gap-3">
          <button
            type="button"
            className={fitActionButtonClass()}
            onClick={() => {
              dismiss();
              router.push("/simulation");
            }}
          >
            {welcomeCopy.trySimulation}
          </button>
          <button type="button" className={choiceButtonClass(false)} onClick={dismiss}>
            {welcomeCopy.enterSite}
          </button>
        </div>
      </div>
    </div>
  );
}

function subscribeNothing() {
  return () => {};
}

function readWelcome(): string | null {
  try {
    return localStorage.getItem(welcomeStorageKey);
  } catch {
    return null;
  }
}
