import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { Providers } from "./providers";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Driver (DVR)",
  description:
    "The treasury is the student. You hold DVR, so you are the instructor.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="flex min-h-full flex-col bg-background text-ink">
        <Providers>
          <a
            href="#content"
            className="absolute left-4 top-4 z-[60] -translate-y-24 rounded-md bg-background px-3 py-2 text-ink focus:translate-y-0"
          >
            Skip to content
          </a>
          <SiteHeader />
          <div id="content" className="flex flex-1 flex-col">
            {children}
          </div>
          <SiteFooter />
        </Providers>
      </body>
    </html>
  );
}
