import { ReferenceShell } from "@/components/layout/reference-shell";

export default function PanelLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return <ReferenceShell>{children}</ReferenceShell>;
}