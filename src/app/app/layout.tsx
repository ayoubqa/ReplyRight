import { Suspense } from "react";
import { connection } from "next/server";
import { Logo } from "@/components/brand/Logo";
import { AppNav, BottomNav } from "@/components/app/AppNav";
import { ModeBadge } from "@/components/app/ModeBadge";
import { getAiStatus } from "@/lib/ai";

async function LiveModeBadge() {
  // AI configuration is read from env at request time, never baked into the build.
  await connection();
  return <ModeBadge mode={getAiStatus().mode} />;
}

export default function AppLayout({ children }: LayoutProps<"/app">) {
  return (
    <div className="relative min-h-dvh">
      <div className="glow pointer-events-none fixed inset-x-0 top-0 h-[420px] opacity-70" aria-hidden />
      <header className="sticky top-0 z-30 border-b border-line bg-ink/75 pt-[env(safe-area-inset-top)] backdrop-blur-xl">
        <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-4 sm:px-6">
          <Logo href="/" />
          <div className="flex items-center gap-2">
            <AppNav />
            <Suspense fallback={<span className="h-6 w-20 rounded-full border border-line" />}>
              <LiveModeBadge />
            </Suspense>
          </div>
        </div>
      </header>
      <main className="relative mx-auto max-w-6xl px-4 pt-6 pb-[calc(6rem+env(safe-area-inset-bottom))] sm:px-6 md:pb-16">
        {children}
      </main>
      <BottomNav />
    </div>
  );
}
