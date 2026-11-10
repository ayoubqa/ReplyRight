"use client";

import { useEffect, useRef, useState } from "react";
import { Button, cn } from "@/components/ui/primitives";

export interface EditableReply {
  label: string;
  text: string;
  why: string;
  original: string;
}

async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // Fallback for browsers without async clipboard permissions.
    const el = document.createElement("textarea");
    el.value = text;
    el.setAttribute("readonly", "");
    el.style.position = "fixed";
    el.style.opacity = "0";
    document.body.appendChild(el);
    el.select();
    const ok = document.execCommand("copy");
    el.remove();
    return ok;
  }
}

export function ReplyCard({
  reply,
  index,
  demo,
  onChange,
}: {
  reply: EditableReply;
  index: number;
  demo: boolean;
  onChange: (text: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [copied, setCopied] = useState<"ok" | "fail" | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const edited = reply.text !== reply.original;

  useEffect(() => {
    if (editing) {
      const el = textareaRef.current;
      el?.focus();
      el?.setSelectionRange(el.value.length, el.value.length);
    }
  }, [editing]);

  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(null), 1800);
    return () => clearTimeout(t);
  }, [copied]);

  return (
    <article
      className="animate-rise rounded-3xl border border-line bg-surface/90 p-4 sm:p-5"
      style={{ animationDelay: `${index * 90}ms` }}
      aria-label={`Reply option ${index + 1}: ${reply.label}`}
    >
      <div className="flex items-center justify-between gap-3">
        <p className="flex items-center gap-2 text-[12px] font-medium text-accent">
          <span className="flex size-5 items-center justify-center rounded-full bg-accent-soft text-[10px]">{index + 1}</span>
          {reply.label}
        </p>
        <div className="flex items-center gap-2">
          {demo && (
            <span className="rounded-full border border-warn/30 px-2 py-0.5 text-[10px] font-medium text-warn">Sample</span>
          )}
          {edited && !editing && <span className="text-[11px] text-faint">Edited</span>}
        </div>
      </div>

      {editing ? (
        <textarea
          ref={textareaRef}
          value={reply.text}
          onChange={(e) => onChange(e.target.value)}
          rows={3}
          maxLength={1000}
          aria-label="Edit reply"
          className="mt-3 w-full resize-none rounded-2xl border border-accent/40 bg-ink/60 px-3.5 py-3 text-[15px] leading-relaxed outline-none focus:border-accent"
        />
      ) : (
        <p className="mt-3 rounded-2xl rounded-br-md bg-gradient-to-br from-accent-strong to-[#6d4be0] px-4 py-3 text-[15px] leading-relaxed text-white shadow-[0_10px_30px_-12px_rgb(139_92_246/0.7)] whitespace-pre-wrap">
          {reply.text || <span className="opacity-60">Empty reply</span>}
        </p>
      )}

      <p className="mt-3 text-[13px] leading-relaxed text-muted">{reply.why}</p>

      <div className="mt-4 flex items-center gap-2">
        <Button
          size="sm"
          variant={copied === "ok" ? "secondary" : "primary"}
          onClick={async () => setCopied((await copyText(reply.text)) ? "ok" : "fail")}
          disabled={!reply.text.trim()}
          className="min-w-[92px]"
        >
          {copied === "ok" ? (
            <>
              <CheckIcon /> Copied
            </>
          ) : (
            <>
              <CopyIcon /> Copy
            </>
          )}
        </Button>
        <Button size="sm" variant="secondary" onClick={() => setEditing((v) => !v)}>
          {editing ? "Done" : "Edit"}
        </Button>
        {edited && (
          <Button size="sm" variant="ghost" onClick={() => onChange(reply.original)}>
            Undo edits
          </Button>
        )}
        <span aria-live="polite" className={cn("ml-auto text-[12px]", copied === "fail" ? "text-danger" : "sr-only")}>
          {copied === "fail" ? "Couldn’t copy. Select the text instead." : copied === "ok" ? "Copied to clipboard" : ""}
        </span>
      </div>
    </article>
  );
}

function CopyIcon() {
  return (
    <svg viewBox="0 0 16 16" className="size-3.5" fill="none" aria-hidden>
      <rect x="5" y="5" width="8.5" height="8.5" rx="2" stroke="currentColor" strokeWidth="1.5" />
      <path d="M10.5 3.5V3a1.5 1.5 0 0 0-1.5-1.5H4A1.5 1.5 0 0 0 2.5 3v5A1.5 1.5 0 0 0 4 9.5h.5" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg viewBox="0 0 16 16" className="size-3.5 text-accent" fill="none" aria-hidden>
      <path d="M3.5 8.5l3 3 6-6.5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
