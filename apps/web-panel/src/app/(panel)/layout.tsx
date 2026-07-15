import { PanelHeader } from "@/components/layout/panel-header";
import { PanelSidebar } from "@/components/layout/panel-sidebar";

export default function PanelLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <div className="min-h-screen bg-slate-100 lg:flex">
      <PanelSidebar />
      <div className="min-w-0 flex-1">
        <PanelHeader />
        <main className="px-5 py-6 md:px-8 md:py-8">
          <div className="mx-auto max-w-[1600px]">{children}</div>
        </main>
      </div>
    </div>
  );
}