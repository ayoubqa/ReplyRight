"use client";

import { Button, Card, Eyebrow, Spinner } from "@/components/ui/primitives";
import type { ReplyResponse } from "@/lib/domain/replies";
import { QUICK_TWEAKS } from "@/lib/domain/tones";
import { ReplyCard, type EditableReply } from "./ReplyCard";

export function ResultsEmpty() {
  return (
    <Card className="p-6 sm:p-8">
      <Eyebrow>Your replies</Eyebrow>
      <h2 className="mt-3 font-display text-3xl leading-tight">Three ways to say it, ready when you are.</h2>
      <ul className="mt-6 space-y-3 text-[13px] leading-relaxed text-muted">
        <li className="flex gap-3">
          <Bullet /> Include a few messages before the last one so the replies have context.
        </li>
        <li className="flex gap-3">
          <Bullet /> Crop out anything you’d rather not share, like names or photos.
        </li>
        <li className="flex gap-3">
          <Bullet /> Set your language, humour and texting style once in your profile.
        </li>
      </ul>
    </Card>
  );
}

export function ResultsLoading({ hasImages }: { hasImages: boolean }) {
  return (
    <div className="space-y-3" aria-busy="true" aria-live="polite">
      <Card className="p-5">
        <p className="flex items-center gap-2 text-[13px] text-muted">
          <Spinner className="text-accent" />
          {hasImages ? "Reading your screenshots…" : "Reading the conversation…"}
        </p>
        <div className="skeleton mt-4 h-3 w-4/5 rounded-full" />
        <div className="skeleton mt-2.5 h-3 w-3/5 rounded-full" />
      </Card>
      {[0, 1, 2].map((i) => (
        <Card key={i} className="p-5">
          <div className="skeleton h-3 w-24 rounded-full" />
          <div className="skeleton mt-4 h-14 w-full rounded-2xl" style={{ animationDelay: `${i * 120}ms` }} />
          <div className="skeleton mt-3 h-3 w-2/3 rounded-full" />
        </Card>
      ))}
    </div>
  );
}

export function ResultsError({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <Card className="border-danger/25 p-6" >
      <div role="alert">
        <p className="text-sm font-medium text-fg">Couldn’t write replies</p>
        <p className="mt-1.5 text-[13px] leading-relaxed text-muted">{message}</p>
      </div>
      <Button size="sm" variant="secondary" className="mt-4" onClick={onRetry}>
        Try again
      </Button>
    </Card>
  );
}

export function ResultsView({
  response,
  replies,
  onEdit,
  onRegenerate,
  onTweak,
  regenerating,
}: {
  response: ReplyResponse;
  replies: EditableReply[];
  onEdit: (index: number, text: string) => void;
  onRegenerate: () => void;
  onTweak: (instruction: string) => void;
  regenerating: boolean;
}) {
  const { result, mode } = response;
  const demo = mode === "demo";

  return (
    <div className="space-y-3">
      {demo && (
        <div className="animate-fade rounded-2xl border border-warn/25 bg-warn/[0.06] px-4 py-3 text-[13px] leading-relaxed text-warn">
          <strong className="font-semibold">Demo mode.</strong> These are pre-written samples, not AI-generated replies.
          Add an AI provider key to get replies written for your conversation.
        </div>
      )}

      <Card className="animate-rise p-5">
        <div className="flex items-center justify-between gap-3">
          <Eyebrow>The read</Eyebrow>
          <span className="rounded-full border border-line px-2.5 py-0.5 text-[11px] text-muted">{result.read.vibe}</span>
        </div>
        <p className="mt-3 text-[15px] leading-relaxed">{result.read.summary}</p>
        {result.read.cues.length > 0 && (
          <div className="mt-4 flex flex-wrap gap-1.5">
            {result.read.cues.map((cue) => (
              <span key={cue} className="rounded-full bg-surface-3 px-2.5 py-1 text-[12px] text-muted">
                {cue}
              </span>
            ))}
          </div>
        )}
        {!demo && (
          <p className="mt-4 text-[11px] text-faint">An interpretation, not a verdict. Only they know what they meant.</p>
        )}
        {result.transcript.length > 0 && (
          <details className="group mt-4 rounded-2xl border border-line bg-ink/40 px-4 py-3">
            <summary className="cursor-pointer list-none text-[12px] font-medium text-muted marker:hidden group-open:text-fg">
              What we read from your screenshots ({result.transcript.length})
            </summary>
            <ol className="mt-3 space-y-1.5">
              {result.transcript.map((line, i) => (
                <li
                  key={i}
                  className={
                    line.speaker === "me"
                      ? "ml-auto w-fit max-w-[85%] rounded-xl bg-surface-3 px-3 py-1.5 text-[12px]"
                      : "w-fit max-w-[85%] rounded-xl bg-surface-2 px-3 py-1.5 text-[12px] text-muted"
                  }
                >
                  {line.speaker === "unknown" && <span className="mr-1 text-faint">?</span>}
                  {line.text}
                </li>
              ))}
            </ol>
          </details>
        )}
      </Card>

      {result.headsUp && (
        <div className="animate-rise rounded-2xl border border-accent/25 bg-accent-soft px-4 py-3 text-[13px] leading-relaxed">
          <span className="font-medium text-accent">Heads up · </span>
          {result.headsUp}
        </div>
      )}

      {replies.length === 0 ? (
        <Card className="p-5 text-[13px] leading-relaxed text-muted">
          No reply suggestions this time. Try a clearer screenshot or paste the messages as text.
        </Card>
      ) : (
        <div className={regenerating ? "pointer-events-none space-y-3 opacity-50 transition-opacity" : "space-y-3 transition-opacity"}>
          {replies.map((reply, i) => (
            <ReplyCard key={`${i}-${reply.original}`} reply={reply} index={i} demo={demo} onChange={(t) => onEdit(i, t)} />
          ))}
        </div>
      )}

      <div className="pt-2">
        <div className="flex flex-wrap items-center gap-2">
          <Button variant="secondary" size="sm" onClick={onRegenerate} disabled={regenerating}>
            {regenerating ? <Spinner /> : <RefreshIcon />}
            {regenerating ? "Writing…" : "Regenerate"}
          </Button>
          {QUICK_TWEAKS.map((tweak) => (
            <Button key={tweak.label} variant="ghost" size="sm" onClick={() => onTweak(tweak.instruction)} disabled={regenerating} className="border border-line">
              {tweak.label}
            </Button>
          ))}
        </div>
        <p className="mt-3 text-[11px] leading-relaxed text-faint">
          Suggestions are options, not scripts. Send what feels true to you.
        </p>
      </div>
    </div>
  );
}

function Bullet() {
  return <span className="mt-[7px] size-1.5 shrink-0 rounded-full bg-accent" />;
}

function RefreshIcon() {
  return (
    <svg viewBox="0 0 16 16" className="size-3.5" fill="none" aria-hidden>
      <path d="M13 8a5 5 0 1 1-1.5-3.6M13 2.5V5h-2.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
