"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Button, Eyebrow, SegmentedControl, Spinner, cn } from "@/components/ui/primitives";
import { ApiClientError, requestReplies } from "@/lib/client/api";
import { ImageInputError, prepareScreenshot } from "@/lib/client/image";
import { LIMITS, type GenerationMode, type ReplyResponse } from "@/lib/domain/replies";
import { INSTRUCTION_SUGGESTIONS, TONE_DEFINITIONS, TONES, type Tone } from "@/lib/domain/tones";
import { useProfile } from "@/lib/profile/store";
import type { EditableReply } from "./ReplyCard";
import { ResultsEmpty, ResultsError, ResultsLoading, ResultsView } from "./Results";
import { ScreenshotInput, type Screenshot } from "./ScreenshotInput";

type InputMode = "screenshot" | "text";
type Status = "idle" | "loading" | "success" | "error";

const TONE_OPTIONS = TONES.map((id) => ({ id, label: TONE_DEFINITIONS[id].label, hint: TONE_DEFINITIONS[id].hint }));

export function Composer({ mode }: { mode: GenerationMode }) {
  const [profile] = useProfile();

  const [inputMode, setInputMode] = useState<InputMode>("screenshot");
  const [screenshots, setScreenshots] = useState<Screenshot[]>([]);
  const [processingImages, setProcessingImages] = useState(false);
  const [imageError, setImageError] = useState<string | null>(null);
  const [conversation, setConversation] = useState("");
  const [toneOverride, setToneOverride] = useState<Tone | null>(null);
  const [instruction, setInstruction] = useState("");

  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);
  const [response, setResponse] = useState<ReplyResponse | null>(null);
  const [replies, setReplies] = useState<EditableReply[]>([]);
  const [seen, setSeen] = useState<string[]>([]);
  const [regenerating, setRegenerating] = useState(false);

  const abortRef = useRef<AbortController | null>(null);
  const resultsRef = useRef<HTMLElement>(null);
  const screenshotsRef = useRef(screenshots);
  useEffect(() => {
    screenshotsRef.current = screenshots;
  }, [screenshots]);
  const lastRequestRef = useRef<{ extraInstruction?: string; regenerate: boolean } | null>(null);

  const tone = toneOverride ?? profile.preferredTone;
  const activeImages = useMemo(() => (inputMode === "screenshot" ? screenshots : []), [inputMode, screenshots]);
  const activeText = inputMode === "text" ? conversation.trim() : "";
  const hasInput = activeImages.length > 0 || activeText.length >= 2;
  const busy = status === "loading" || regenerating;

  // Release preview URLs when the composer unmounts.
  useEffect(() => () => screenshotsRef.current.forEach((s) => URL.revokeObjectURL(s.url)), []);

  const addFiles = useCallback(async (files: File[]) => {
    setImageError(null);
    const room = LIMITS.maxImages - screenshotsRef.current.length;
    if (room <= 0) {
      setImageError(`You can add up to ${LIMITS.maxImages} screenshots.`);
      return;
    }
    const accepted = files.slice(0, room);
    if (files.length > room) setImageError(`Only the first ${room} image${room > 1 ? "s were" : " was"} added (max ${LIMITS.maxImages}).`);

    setProcessingImages(true);
    const added: Screenshot[] = [];
    for (const file of accepted) {
      try {
        const blob = await prepareScreenshot(file);
        added.push({ id: crypto.randomUUID(), blob, url: URL.createObjectURL(blob) });
      } catch (err) {
        setImageError(err instanceof ImageInputError ? err.message : "Couldn’t add that image.");
      }
    }
    setScreenshots((prev) => [...prev, ...added].slice(0, LIMITS.maxImages));
    setProcessingImages(false);
  }, []);

  const removeScreenshot = (id: string) => {
    setScreenshots((prev) => {
      const target = prev.find((s) => s.id === id);
      if (target) URL.revokeObjectURL(target.url);
      return prev.filter((s) => s.id !== id);
    });
    setImageError(null);
  };

  // Paste screenshots straight from the clipboard.
  useEffect(() => {
    const onPaste = (event: ClipboardEvent) => {
      const files = Array.from(event.clipboardData?.files ?? []).filter((f) => f.type.startsWith("image/"));
      if (files.length) {
        event.preventDefault();
        setInputMode("screenshot");
        void addFiles(files);
      }
    };
    document.addEventListener("paste", onPaste);
    return () => document.removeEventListener("paste", onPaste);
  }, [addFiles]);

  const generate = useCallback(
    async ({ regenerate = false, extraInstruction }: { regenerate?: boolean; extraInstruction?: string } = {}) => {
      if (!hasInput) return;
      abortRef.current?.abort();
      const controller = new AbortController();
      abortRef.current = controller;
      lastRequestRef.current = { regenerate, extraInstruction };

      setError(null);
      if (regenerate && response) {
        setRegenerating(true);
      } else {
        setStatus("loading");
        if (window.matchMedia("(max-width: 1023px)").matches) {
          requestAnimationFrame(() => resultsRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }));
        }
      }

      const combinedInstruction = [instruction.trim(), extraInstruction].filter(Boolean).join(" ").slice(0, LIMITS.instructionChars);
      const avoid = regenerate ? seen.slice(-LIMITS.avoidReplies) : [];

      try {
        const res = await requestReplies(
          { conversation: activeText, tone, instruction: combinedInstruction, profile, avoid },
          activeImages.map((s) => s.blob),
          controller.signal,
        );
        const texts = res.result.replies.map((r) => r.text);
        setResponse(res);
        setReplies(res.result.replies.map((r) => ({ ...r, original: r.text })));
        setSeen((prev) => (regenerate ? [...prev, ...texts] : texts).slice(-LIMITS.avoidReplies));
        setStatus("success");
      } catch (err) {
        if ((err as Error).name === "AbortError") return;
        setError(err instanceof ApiClientError ? err.message : "Something went wrong. Please try again.");
        // Keep existing results visible if a regeneration fails.
        setStatus(regenerate && response ? "success" : "error");
      } finally {
        if (abortRef.current === controller) setRegenerating(false);
      }
    },
    [hasInput, instruction, seen, activeText, tone, profile, activeImages, response],
  );

  const onSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    void generate();
  };

  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:gap-10">
      <form onSubmit={onSubmit} className="space-y-7 lg:sticky lg:top-20 lg:self-start" noValidate>
        <div className="animate-rise">
          <h1 className="font-display text-[2.6rem] leading-[1.02] tracking-tight sm:text-5xl">
            What did they <em className="text-accent">say?</em>
          </h1>
          <p className="mt-2 text-sm text-muted">Share the conversation and choose how you want to come across.</p>
        </div>

        {/* Input */}
        <section aria-labelledby="input-heading" className="space-y-3">
          <div className="flex items-center justify-between">
            <Eyebrow>
              <span id="input-heading">Conversation</span>
            </Eyebrow>
            <div role="tablist" aria-label="Input type" className="flex rounded-full border border-line bg-surface-2/60 p-0.5">
              {(["screenshot", "text"] as const).map((m) => (
                <button
                  key={m}
                  type="button"
                  role="tab"
                  aria-selected={inputMode === m}
                  onClick={() => setInputMode(m)}
                  className={cn(
                    "rounded-full px-3 py-1 text-[12px] font-medium transition-colors",
                    inputMode === m ? "bg-fg text-ink" : "text-muted hover:text-fg",
                  )}
                >
                  {m === "screenshot" ? "Screenshot" : "Paste text"}
                </button>
              ))}
            </div>
          </div>

          {inputMode === "screenshot" ? (
            <ScreenshotInput
              screenshots={screenshots}
              onAdd={(files) => void addFiles(files)}
              onRemove={removeScreenshot}
              processing={processingImages}
              error={imageError}
            />
          ) : (
            <div>
              <textarea
                value={conversation}
                onChange={(e) => setConversation(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                    e.preventDefault();
                    void generate();
                  }
                }}
                rows={7}
                maxLength={LIMITS.conversationChars}
                aria-label="Paste the conversation"
                placeholder={"Them: so what are you up to this weekend?\nMe: not much, might check out that new ramen place\nThem: wait which one, I’ve been dying to try it"}
                className="w-full resize-y rounded-3xl border border-line-strong bg-surface-2/40 px-4 py-3.5 text-[15px] leading-relaxed outline-none placeholder:text-faint focus:border-accent/60 focus:bg-surface-2/70"
              />
              <p className="mt-2 flex justify-between text-[12px] text-faint">
                <span>Label lines “Them:” and “Me:” for best results.</span>
                <span>
                  {conversation.length}/{LIMITS.conversationChars}
                </span>
              </p>
            </div>
          )}
        </section>

        {/* Tone */}
        <section aria-labelledby="tone-heading" className="space-y-3">
          <div className="flex items-center justify-between">
            <Eyebrow>
              <span id="tone-heading">Tone</span>
            </Eyebrow>
            {toneOverride && toneOverride !== profile.preferredTone && (
              <button type="button" onClick={() => setToneOverride(null)} className="text-[12px] text-faint hover:text-fg">
                Use profile default
              </button>
            )}
          </div>
          <SegmentedControl label="Tone" options={TONE_OPTIONS} value={tone} onChange={setToneOverride} />
        </section>

        {/* Instruction */}
        <section aria-labelledby="instruction-heading" className="space-y-3">
          <Eyebrow>
            <span id="instruction-heading">
              Anything specific? <span className="normal-case tracking-normal text-faint/80">(optional)</span>
            </span>
          </Eyebrow>
          <input
            value={instruction}
            onChange={(e) => setInstruction(e.target.value)}
            maxLength={LIMITS.instructionChars}
            placeholder="e.g. Make it less eager"
            aria-label="Custom instruction"
            className="h-12 w-full rounded-2xl border border-line-strong bg-surface-2/40 px-4 text-[15px] outline-none placeholder:text-faint focus:border-accent/60"
          />
          <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 sm:mx-0 sm:flex-wrap sm:px-0">
            {INSTRUCTION_SUGGESTIONS.map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setInstruction(s)}
                className={cn(
                  "shrink-0 rounded-full border px-3 py-1.5 text-[12px] transition-colors",
                  instruction === s ? "border-accent/50 bg-accent-soft text-fg" : "border-line text-muted hover:border-line-strong hover:text-fg",
                )}
              >
                {s}
              </button>
            ))}
          </div>
        </section>

        <div className="sticky bottom-[calc(4.75rem+env(safe-area-inset-bottom))] z-20 -mx-4 bg-gradient-to-t from-ink via-ink/95 to-transparent px-4 pt-4 pb-1 md:static md:mx-0 md:bg-none md:p-0">
          <Button type="submit" size="lg" className="w-full" disabled={!hasInput || busy || processingImages}>
            {status === "loading" ? (
              <>
                <Spinner /> Writing your replies…
              </>
            ) : (
              <>Get 3 replies</>
            )}
          </Button>
          {mode === "demo" && (
            <p className="mt-2 text-center text-[11px] text-faint">
              Demo mode: results are samples and your conversation isn’t analysed.
            </p>
          )}
        </div>
        <p className="hidden text-[12px] text-faint md:block">
          Replies use your{" "}
          <Link href="/app/profile" className="text-muted underline-offset-2 hover:text-fg hover:underline">
            communication profile
          </Link>
          .
        </p>
      </form>

      <section ref={resultsRef} aria-label="Reply suggestions" className="scroll-mt-20" aria-live="polite">
        {status === "idle" && <ResultsEmpty />}
        {status === "loading" && <ResultsLoading hasImages={activeImages.length > 0} />}
        {status === "error" && error && <ResultsError message={error} onRetry={() => void generate(lastRequestRef.current ?? {})} />}
        {status === "success" && response && (
          <>
            {error && (
              <p role="alert" className="mb-3 rounded-2xl border border-danger/25 px-4 py-3 text-[13px] text-danger">
                {error}
              </p>
            )}
            <ResultsView
              response={response}
              replies={replies}
              regenerating={regenerating}
              onEdit={(index, text) => setReplies((prev) => prev.map((r, i) => (i === index ? { ...r, text } : r)))}
              onRegenerate={() => void generate({ regenerate: true })}
              onTweak={(extra) => void generate({ regenerate: true, extraInstruction: extra })}
            />
          </>
        )}
      </section>
    </div>
  );
}
