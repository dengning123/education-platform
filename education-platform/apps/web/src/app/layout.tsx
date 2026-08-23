import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import "./globals.css";

export const metadata: Metadata = {
  title: "Education Platform",
  description: "Private student planning workspace",
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <div className="page-frame">
          <header className="site-header">
            <Link className="brand" href="/" aria-label="Education Platform home">
              <span className="brand-mark" aria-hidden="true">E</span>
              <span>Education Platform</span>
            </Link>
            <span className="environment-label">Private workspace</span>
          </header>
          <main className="main-content">{children}</main>
          <footer className="site-footer">
            Identity is handled by Supabase Auth. Data access remains enforced by server boundaries and RLS.
          </footer>
        </div>
      </body>
    </html>
  );
}
