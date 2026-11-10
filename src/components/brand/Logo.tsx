import Link from "next/link";
import { cn } from "@/components/ui/primitives";

export function LogoMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={cn("size-7", className)} aria-hidden>
      <defs>
        <linearGradient id="rr-g" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#c4b5fd" />
          <stop offset="1" stopColor="#7c3aed" />
        </linearGradient>
      </defs>
      <rect width="32" height="32" rx="10" fill="#0e0e12" />
      <rect x="0.5" y="0.5" width="31" height="31" rx="9.5" fill="none" stroke="rgb(255 255 255 / 0.12)" />
      <path d="M9 11.5c0-1.4 1.1-2.5 2.5-2.5h9c1.4 0 2.5 1.1 2.5 2.5v5c0 1.4-1.1 2.5-2.5 2.5H15l-3.6 3.1c-.4.3-.9 0-.9-.4V19.2A2.5 2.5 0 0 1 9 16.5v-5Z" fill="url(#rr-g)" />
      <path d="M13 14.2l1.9 1.8 3.9-3.8" stroke="#0e0e12" strokeWidth="1.8" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function Logo({ href = "/", className }: { href?: string; className?: string }) {
  return (
    <Link href={href} className={cn("inline-flex items-center gap-2.5", className)} aria-label="ReplyRight home">
      <LogoMark />
      <span className="text-[15px] font-semibold tracking-tight">ReplyRight</span>
    </Link>
  );
}
