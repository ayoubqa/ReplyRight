import "server-only";
import type { TranscriptLine } from "@/lib/domain/contracts";
import { CRUSH_STAGE_LABELS, LANGUAGES, TONE_GUIDANCE, type Crush, type Voice } from "@/lib/domain/voice";

const HUMOUR_TEXT: Record<Voice["humour"], string> = {
  minimal: "Minimal. Sincere first; humour only if it comes naturally.",
  light: "Light. A smile here and there.",
  witty: "Witty. Quick and clever.",
  dry: "Dry. Deadpan and understated.",
  goofy: "Goofy. Silly and unserious.",
};
const EMOJI_TEXT: Record<Voice["emoji"], string> = {
  none: "Never uses emoji.",
  rare: "Sometimes. At most one, only when it adds something.",
  often: "Often. Emoji are part of how they text, but still not every message.",
};
const LENGTH_TEXT: Record<Voice["length"], string> = {
  short: "Short. Usually one line.",
  medium: "Medium. One or two sentences.",
  long: "Longer. A few sentences is normal for them.",
};
const VOCAB_TEXT: Record<Voice["vocabulary"], string> = {
  casual: "Casual. Relaxed spelling and everyday slang are fine.",
  balanced: "Everyday. Neither slangy nor formal.",
  polished: "Polished. Full words and tidy punctuation, still conversational.",
};
const DIRECT_TEXT: Record<Voice["directness"], string> = {
  gentle: "Gentle. Prefers to suggest rather than state.",
  balanced: "Balanced. Clear without being blunt.",
  bold: "Bold. Says what they mean.",
};
const ROMANCE_TEXT: Record<Voice["romance"], string> = {
  subtle: "Subtle. Shows interest through attention and humour more than declarations.",
  balanced: "Balanced. Comfortable with an occasional sincere compliment.",
  open: "Open. Comfortable saying how they feel.",
};

function languageLabel(id: string): string {
  return LANGUAGES.find((l) => l.id === id)?.label ?? id;
}

export function describeVoice(voice: Voice | undefined, options: { includeSamples: boolean }): string {
  if (!voice) {
    return "<my_voice>\nNo profile yet. Default to short, natural, lightly playful messages.\n</my_voice>";
  }
  const lines = [
    `Default tone: ${voice.defaultTone}. ${TONE_GUIDANCE[voice.defaultTone]}`,
    voice.personality.length ? `Describes themselves as: ${voice.personality.join(", ")}` : null,
    `Humour: ${HUMOUR_TEXT[voice.humour]}`,
    `Emoji: ${EMOJI_TEXT[voice.emoji]}`,
    `Message length: ${LENGTH_TEXT[voice.length]}`,
    `Vocabulary: ${VOCAB_TEXT[voice.vocabulary]}`,
    `Directness: ${DIRECT_TEXT[voice.directness]}`,
    `Romantic expression: ${ROMANCE_TEXT[voice.romance]}`,
    voice.replyLanguage === "match"
      ? "Reply language: match the conversation."
      : `Reply language: always ${languageLabel(voice.replyLanguage)}.`,
    voice.languages.length ? `Languages they text in: ${voice.languages.map(languageLabel).join(", ")}` : null,
    voice.writingStyle ? `How they describe their own texting: ${voice.writingStyle}` : null,
    voice.aboutMe ? `About them (use only when it fits naturally): ${voice.aboutMe}` : null,
  ].filter((line): line is string => Boolean(line));

  if (options.includeSamples && voice.samples.length > 0) {
    lines.push(
      "Messages they have really sent (style reference only: match rhythm, casing, punctuation and emoji habits; never reuse the content):",
      ...voice.samples.map((s) => `- ${s}`),
    );
  }
  return `<my_voice>\n${lines.join("\n")}\n</my_voice>`;
}

export function describeCrush(crush: Crush | undefined): string | null {
  if (!crush) return null;
  const lines = [`Nickname the user gave them: ${crush.alias}`, `Where things stand: ${CRUSH_STAGE_LABELS[crush.stage]}`];
  if (crush.metAt) lines.push(`Where they met: ${crush.metAt}`);
  if (crush.language) lines.push(`Language they prefer to text in: ${crush.language}`);
  if (crush.interests.length) lines.push(`Interests and hobbies: ${crush.interests.join(", ")}`);
  if (crush.background) lines.push(`Background: ${crush.background}`);
  if (crush.preferences) lines.push(`How they like to communicate: ${crush.preferences}`);
  if (crush.details) lines.push(`Details worth remembering: ${crush.details}`);
  if (crush.history) lines.push(`Earlier conversations, in the user's words: ${crush.history}`);
  if (crush.notes) lines.push(`Other notes: ${crush.notes}`);
  lines.push(
    "The user wrote all of this themselves. Use a detail only where it fits this moment naturally, never list it back, and never add facts about this person that are not written here.",
  );
  return `<the_person>\n${lines.join("\n")}\n</the_person>`;
}

const SPEAKER_LABEL = { them: "Them", me: "Me", unknown: "?" } as const;

export function describeConversation(input: { conversation: string; transcript?: TranscriptLine[] }): string | null {
  if (input.transcript && input.transcript.length > 0) {
    const body = input.transcript.map((line) => `${SPEAKER_LABEL[line.speaker]}: ${line.text}`).join("\n");
    return `<conversation>\n${body}\n</conversation>`;
  }
  if (input.conversation) return `<conversation>\n${input.conversation}\n</conversation>`;
  return null;
}

export function joinSections(sections: (string | null | undefined | false)[]): string {
  return sections.filter((s): s is string => Boolean(s)).join("\n\n");
}

export function localeSection(locale: string): string {
  return `<app_locale>${locale || "en"}</app_locale>`;
}
