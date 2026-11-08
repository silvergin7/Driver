"use client";

import { CarMark } from "@/components/logo-mark";

export function TokenIcon({
  token,
  className,
}: {
  token: "dvr" | "musdc";
  className: string;
}) {
  if (token === "dvr") {
    return (
      <span
        aria-hidden="true"
        className={`inline-flex shrink-0 items-center justify-center rounded-md border-2 border-sign bg-white p-px ${className}`}
      >
        <CarMark />
      </span>
    );
  }
  return (
    <svg aria-hidden="true" viewBox="0 0 32 32" className={`shrink-0 ${className}`}>
      <circle cx="16" cy="16" r="16" fill="#2775CA" />
      <path
        d="M11.2 10.2a6.4 6.4 0 0 0 0 11.6"
        fill="none"
        stroke="#fff"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
      <path
        d="M20.8 10.2a6.4 6.4 0 0 1 0 11.6"
        fill="none"
        stroke="#fff"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
      <path
        d="M16 8.2v15.6M19.4 11.4c-.4-1.5-1.6-2.3-3.4-2.3-1.9 0-3.2 1-3.2 2.5 0 1.4.9 2.1 3.3 2.7 2.7.6 4.3 1.5 4.3 3.5 0 1.6-1.5 2.8-3.7 3.1"
        fill="none"
        stroke="#fff"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
