"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/components/ui/primitives";

const ITEMS = [
  { href: "/app", label: "Compose", icon: ComposeIcon },
  { href: "/app/profile", label: "Profile", icon: ProfileIcon },
] as const;

export function AppNav() {
  const pathname = usePathname();
  return (
    <nav className="hidden items-center gap-1 md:flex" aria-label="App">
      {ITEMS.map((item) => {
        const active = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "rounded-full px-3.5 py-1.5 text-sm transition-colors",
              active ? "bg-white/8 text-fg" : "text-muted hover:text-fg",
            )}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}

export function BottomNav() {
  const pathname = usePathname();
  return (
    <nav
      aria-label="App"
      className="fixed inset-x-0 bottom-0 z-30 border-t border-line bg-ink/85 pb-[env(safe-area-inset-bottom)] backdrop-blur-xl md:hidden"
    >
      <div className="mx-auto grid h-16 max-w-md grid-cols-2">
        {ITEMS.map((item) => {
          const active = pathname === item.href;
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex flex-col items-center justify-center gap-1 text-[11px] font-medium transition-colors",
                active ? "text-fg" : "text-faint",
              )}
            >
              <Icon active={active} />
              {item.label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}

function ComposeIcon({ active }: { active: boolean }) {
  return (
    <svg viewBox="0 0 24 24" className={cn("size-5", active && "text-accent")} fill="none" aria-hidden>
      <path
        d="M5 6.5A2.5 2.5 0 0 1 7.5 4h9A2.5 2.5 0 0 1 19 6.5v7a2.5 2.5 0 0 1-2.5 2.5H11l-4.2 3.4a.5.5 0 0 1-.8-.4V16a2.5 2.5 0 0 1-1-2V6.5Z"
        stroke="currentColor"
        strokeWidth="1.6"
        fill={active ? "currentColor" : "none"}
        fillOpacity={active ? 0.15 : 0}
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ProfileIcon({ active }: { active: boolean }) {
  return (
    <svg viewBox="0 0 24 24" className={cn("size-5", active && "text-accent")} fill="none" aria-hidden>
      <circle cx="12" cy="8.5" r="3.5" stroke="currentColor" strokeWidth="1.6" fill={active ? "currentColor" : "none"} fillOpacity={active ? 0.15 : 0} />
      <path d="M5 19.5c1.2-3 3.9-4.5 7-4.5s5.8 1.5 7 4.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}
