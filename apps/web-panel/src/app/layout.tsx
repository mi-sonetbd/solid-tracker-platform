import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Solid Tracker",
    template: "%s | Solid Tracker",
  },
  description:
    "Solid Tracker fleet, device, customer, dealer, billing, and live tracking management platform.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}