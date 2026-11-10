import { z } from "zod";

/**
 * "My Voice": how the user actually texts. Everything here is provided
 * explicitly by the user in the app. Nothing is inferred from other apps.
 * Mirrored in ios/.../ReplyRightCore/Models/VoiceProfile.swift.
 */
export const TONES = ["playful", "flirty", "confident", "charming", "subtle", "warm"] as const;
export type Tone = (typeof TONES)[number];

export const TONE_GUIDANCE: Record<Tone, string> = {
  playful: "Light-hearted and fun, with gentle teasing.",
  flirty: "Warm and openly interested, a little bold.",
  confident: "Direct, relaxed and sure of itself.",
  charming: "Attentive and thoughtful, makes them feel noticed.",
  subtle: "Understated and low-pressure; interest is implied rather than declared.",
  warm: "Kind, sincere and affectionate without being intense.",
};

export const PERSONALITIES = ["funny", "shy", "confident", "romantic", "reserved"] as const;
export const HUMOUR = ["minimal", "light", "witty", "dry", "goofy"] as const;
export const EMOJI = ["none", "rare", "often"] as const;
export const LENGTHS = ["short", "medium", "long"] as const;
export const VOCABULARY = ["casual", "balanced", "polished"] as const;
export const DIRECTNESS = ["gentle", "balanced", "bold"] as const;
export const ROMANCE = ["subtle", "balanced", "open"] as const;

/** Languages replies can be written in. Add a row here to enable another. */
export const LANGUAGES = [
  { id: "en", label: "English" },
  { id: "es", label: "Spanish" },
  { id: "fr", label: "French" },
] as const;
export const LANGUAGE_IDS = LANGUAGES.map((l) => l.id) as ["en", "es", "fr"];
export const REPLY_LANGUAGES = ["match", ...LANGUAGE_IDS] as const;

export const voiceSchema = z.object({
  defaultTone: z.enum(TONES).default("playful"),
  personality: z.array(z.enum(PERSONALITIES)).max(3).default([]),
  humour: z.enum(HUMOUR).default("light"),
  emoji: z.enum(EMOJI).default("rare"),
  length: z.enum(LENGTHS).default("short"),
  vocabulary: z.enum(VOCABULARY).default("casual"),
  directness: z.enum(DIRECTNESS).default("balanced"),
  romance: z.enum(ROMANCE).default("balanced"),
  replyLanguage: z.enum(REPLY_LANGUAGES).default("match"),
  languages: z.array(z.enum(LANGUAGE_IDS)).max(LANGUAGE_IDS.length).default([]),
  writingStyle: z.string().trim().max(300).default(""),
  aboutMe: z.string().trim().max(300).default(""),
  /** Messages the user has really sent, offered voluntarily as style examples. */
  samples: z.array(z.string().trim().min(1).max(280)).max(8).default([]),
});
export type Voice = z.infer<typeof voiceSchema>;

export const CRUSH_STAGES = ["new_match", "talking", "been_on_dates", "seeing_each_other", "reconnecting"] as const;
export type CrushStage = (typeof CRUSH_STAGES)[number];

export const CRUSH_STAGE_LABELS: Record<CrushStage, string> = {
  new_match: "We just matched or just met",
  talking: "We've been talking for a while",
  been_on_dates: "We've been on a date or two",
  seeing_each_other: "We're seeing each other",
  reconnecting: "We're reconnecting after a gap",
};

/** Optional context about the person, entered by the user under an alias. */
export const crushSchema = z.object({
  alias: z.string().trim().min(1).max(40),
  stage: z.enum(CRUSH_STAGES).default("talking"),
  notes: z.string().trim().max(400).default(""),
});
export type Crush = z.infer<typeof crushSchema>;
