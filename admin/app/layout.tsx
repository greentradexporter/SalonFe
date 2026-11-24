import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SalonFe Control Center",
  description: "Real-time salon operations and booking supervision for SalonFe.",
  icons: {
    icon: "/salonfe-icon.png",
    shortcut: "/salonfe-icon.png",
    apple: "/salonfe-icon.png",
  },
  openGraph: {
    title: "SalonFe Control Center",
    description: "Real-time salon operations and booking supervision for SalonFe.",
    type: "website",
  },
  twitter: {
    card: "summary",
    title: "SalonFe Control Center",
    description: "Real-time salon operations and booking supervision for SalonFe.",
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
