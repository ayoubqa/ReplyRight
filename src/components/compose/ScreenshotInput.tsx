"use client";

import { useRef, useState } from "react";
import { cn } from "@/components/ui/primitives";
import { LIMITS } from "@/lib/domain/replies";

export interface Screenshot {
  id: string;
  blob: Blob;
  url: string;
}

export function ScreenshotInput({
  screenshots,
  onAdd,
  onRemove,
  processing,
  error,
}: {
  screenshots: Screenshot[];
  onAdd: (files: File[]) => void;
  onRemove: (id: string) => void;
  processing: boolean;
  error: string | null;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);
  const full = screenshots.length >= LIMITS.maxImages;

  const openPicker = () => inputRef.current?.click();

  return (
    <div>
      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp,image/gif,image/heic"
        multiple
        className="sr-only"
        aria-label="Upload conversation screenshots"
        onChange={(e) => {
          const files = Array.from(e.target.files ?? []);
          if (files.length) onAdd(files);
          e.target.value = "";
        }}
      />

      {screenshots.length === 0 ? (
        <button
          type="button"
          onClick={openPicker}
          onDragOver={(e) => {
            e.preventDefault();
            setDragging(true);
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={(e) => {
            e.preventDefault();
            setDragging(false);
            onAdd(Array.from(e.dataTransfer.files));
          }}
          className={cn(
            "group flex w-full flex-col items-center justify-center rounded-3xl border border-dashed px-6 py-10 text-center transition-colors",
            dragging ? "border-accent bg-accent-soft" : "border-line-strong bg-surface-2/40 hover:border-accent/50 hover:bg-surface-2/70",
          )}
        >
          <span className="flex size-12 items-center justify-center rounded-2xl bg-accent-soft text-accent transition-transform group-hover:scale-105">
            {processing ? <Dots /> : <UploadIcon />}
          </span>
          <span className="mt-4 text-[15px] font-medium">Add a screenshot</span>
          <span className="mt-1 text-[13px] text-muted">
            Tap to choose<span className="hidden sm:inline">, drop, or paste</span> · up to {LIMITS.maxImages}
          </span>
        </button>
      ) : (
        <div className="no-scrollbar -mx-1 flex gap-3 overflow-x-auto px-1 py-1">
          {screenshots.map((shot, i) => (
            <div
              key={shot.id}
              className="relative h-44 w-28 shrink-0 animate-rise overflow-hidden rounded-2xl border border-line bg-surface-2"
            >
              {/* eslint-disable-next-line @next/next/no-img-element -- local object URL preview */}
              <img src={shot.url} alt={`Screenshot ${i + 1}`} className="size-full object-cover object-top" />
              <span className="absolute bottom-1.5 left-1.5 rounded-full bg-black/70 px-2 py-0.5 text-[10px] font-medium backdrop-blur">
                {i + 1}
              </span>
              <button
                type="button"
                onClick={() => onRemove(shot.id)}
                aria-label={`Remove screenshot ${i + 1}`}
                className="absolute top-1.5 right-1.5 flex size-7 items-center justify-center rounded-full bg-black/70 text-white backdrop-blur transition hover:bg-black"
              >
                <svg viewBox="0 0 16 16" className="size-3.5" fill="none" aria-hidden>
                  <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
                </svg>
              </button>
            </div>
          ))}
          {!full && (
            <button
              type="button"
              onClick={openPicker}
              className="flex h-44 w-28 shrink-0 flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-line-strong text-xs text-muted transition hover:border-accent/50 hover:text-fg"
            >
              {processing ? <Dots /> : <span className="text-2xl leading-none font-light">+</span>}
              Add more
            </button>
          )}
        </div>
      )}

      {error && (
        <p role="alert" className="mt-3 text-[13px] text-danger">
          {error}
        </p>
      )}
      <p className="mt-3 flex items-start gap-2 text-[12px] leading-relaxed text-faint">
        <LockIcon />
        Resized on your device and processed in memory. Screenshots are never stored.
      </p>
    </div>
  );
}

function UploadIcon() {
  return (
    <svg viewBox="0 0 24 24" className="size-5" fill="none" aria-hidden>
      <rect x="4" y="4" width="16" height="16" rx="4" stroke="currentColor" strokeWidth="1.6" />
      <path d="M8.5 15l2.3-2.6a1 1 0 0 1 1.5 0L15.5 16M14 13.5l.9-1a1 1 0 0 1 1.5 0L19 15" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="9.5" cy="9" r="1.3" fill="currentColor" />
    </svg>
  );
}

function LockIcon() {
  return (
    <svg viewBox="0 0 16 16" className="mt-0.5 size-3.5 shrink-0" fill="none" aria-hidden>
      <rect x="3" y="7" width="10" height="7" rx="2" stroke="currentColor" strokeWidth="1.3" />
      <path d="M5.5 7V5.5a2.5 2.5 0 0 1 5 0V7" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  );
}

function Dots() {
  return (
    <span className="flex gap-1" aria-label="Processing">
      {[0, 1, 2].map((i) => (
        <span key={i} className="size-1.5 animate-pulse rounded-full bg-current" style={{ animationDelay: `${i * 150}ms` }} />
      ))}
    </span>
  );
}
