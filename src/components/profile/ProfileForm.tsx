"use client";

import { useEffect, useState, type ReactNode } from "react";
import { Button, ButtonLink, Card, Eyebrow, SegmentedControl } from "@/components/ui/primitives";
import {
  DEFAULT_PROFILE,
  EMOJI_USAGE,
  HUMOUR_STYLES,
  LANGUAGES,
  MESSAGE_LENGTHS,
  type CommunicationProfile,
} from "@/lib/domain/profile";
import { TONE_DEFINITIONS, TONES } from "@/lib/domain/tones";
import { useProfile } from "@/lib/profile/store";

const TONE_OPTIONS = TONES.map((id) => ({ id, label: TONE_DEFINITIONS[id].label, hint: TONE_DEFINITIONS[id].hint }));

export function ProfileForm() {
  const [profile, save, hydrated] = useProfile();
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (!saved) return;
    const t = setTimeout(() => setSaved(false), 1500);
    return () => clearTimeout(t);
  }, [saved]);

  const update = <K extends keyof CommunicationProfile>(key: K, value: CommunicationProfile[K]) => {
    save({ ...profile, [key]: value });
    setSaved(true);
  };

  return (
    <div className="mx-auto max-w-2xl">
      <div className="animate-rise">
        <h1 className="font-display text-[2.6rem] leading-[1.02] tracking-tight sm:text-5xl">
          How you <em className="text-accent">talk.</em>
        </h1>
        <p className="mt-2 max-w-md text-sm leading-relaxed text-muted">
          Set this once so every suggestion sounds like you. Saved automatically on this device only.
        </p>
      </div>

      <div className={hydrated ? "mt-8 space-y-4 animate-fade" : "mt-8 space-y-4 opacity-0"}>
        <Section title="Default tone" description="Preselected each time you compose. You can still change it per reply.">
          <SegmentedControl label="Default tone" options={TONE_OPTIONS} value={profile.preferredTone} onChange={(v) => update("preferredTone", v)} />
        </Section>

        <Section title="Language" description="Which language replies should be written in.">
          <label className="relative block">
            <span className="sr-only">Reply language</span>
            <select
              value={profile.language}
              onChange={(e) => update("language", e.target.value as CommunicationProfile["language"])}
              className="h-12 w-full appearance-none rounded-2xl border border-line-strong bg-surface-2/60 px-4 pr-10 text-[15px] outline-none focus:border-accent/60"
            >
              {LANGUAGES.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.label}
                </option>
              ))}
            </select>
            <svg viewBox="0 0 16 16" className="pointer-events-none absolute top-1/2 right-4 size-4 -translate-y-1/2 text-muted" fill="none" aria-hidden>
              <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </label>
        </Section>

        <Section title="Humour" description="How much and what kind of funny.">
          <SegmentedControl label="Humour" options={HUMOUR_STYLES} value={profile.humour} onChange={(v) => update("humour", v)} />
        </Section>

        <Section title="Message length">
          <SegmentedControl label="Message length" options={MESSAGE_LENGTHS} value={profile.length} onChange={(v) => update("length", v)} />
        </Section>

        <Section title="Emoji">
          <SegmentedControl label="Emoji" options={EMOJI_USAGE} value={profile.emoji} onChange={(v) => update("emoji", v)} />
        </Section>

        <Section title="Writing style" description="How you actually text, so replies match. Optional.">
          <TextField
            label="Writing style"
            value={profile.writingStyle}
            onChange={(v) => update("writingStyle", v)}
            placeholder="e.g. all lowercase, no exclamation marks, I say “haha” not “lol”"
          />
        </Section>

        <Section title="About you" description="A few things that could come up naturally. Optional, never required.">
          <TextField
            label="About you"
            value={profile.aboutMe}
            onChange={(v) => update("aboutMe", v)}
            placeholder="e.g. I climb, cook way too much pasta, and just moved to Lisbon"
          />
        </Section>

        <div className="flex flex-wrap items-center gap-3 pt-2">
          <ButtonLink href="/app">Back to compose</ButtonLink>
          <Button
            variant="ghost"
            onClick={() => {
              save(DEFAULT_PROFILE);
              setSaved(true);
            }}
          >
            Reset to defaults
          </Button>
          <span aria-live="polite" className={saved ? "text-[12px] text-accent transition-opacity" : "text-[12px] opacity-0 transition-opacity"}>
            Saved
          </span>
        </div>
      </div>
    </div>
  );
}

function Section({ title, description, children }: { title: string; description?: string; children: ReactNode }) {
  return (
    <Card className="p-5">
      <Eyebrow>{title}</Eyebrow>
      {description && <p className="mt-1.5 text-[13px] text-muted">{description}</p>}
      <div className="mt-4">{children}</div>
    </Card>
  );
}

function TextField({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}) {
  return (
    <div>
      <textarea
        aria-label={label}
        value={value}
        maxLength={300}
        rows={2}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className="w-full resize-none rounded-2xl border border-line-strong bg-surface-2/40 px-4 py-3 text-[15px] leading-relaxed outline-none placeholder:text-faint focus:border-accent/60"
      />
      <p className="mt-1 text-right text-[11px] text-faint">{value.length}/300</p>
    </div>
  );
}
