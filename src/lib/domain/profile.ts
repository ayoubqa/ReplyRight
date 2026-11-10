import { z } from "zod";
import { TONES } from "./tones";

export const LANGUAGES = [
  { id: "match", label: "Match the conversation" },
  { id: "en", label: "English" },
  { id: "fr", label: "French" },
  { id: "es", label: "Spanish" },
  { id: "de", label: "German" },
  { id: "it", label: "Italian" },
  { id: "pt", label: "Portuguese" },
  { id: "nl", label: "Dutch" },
  { id: "ar", label: "Arabic" },
] as const;

export const HUMOUR_STYLES = [
  { id: "minimal", label: "Minimal", hint: "Sincere first" },
  { id: "light", label: "Light", hint: "A smile here and there" },
  { id: "witty", label: "Witty", hint: "Quick and clever" },
  { id: "dry", label: "Dry", hint: "Deadpan, understated" },
  { id: "goofy", label: "Goofy", hint: "Silly and unserious" },
] as const;

export const MESSAGE_LENGTHS = [
  { id: "short", label: "Short", hint: "One line" },
  { id: "medium", label: "Medium", hint: "One or two sentences" },
  { id: "long", label: "Longer", hint: "A few sentences" },
] as const;

export const EMOJI_USAGE = [
  { id: "none", label: "Never" },
  { id: "rare", label: "Sometimes" },
  { id: "often", label: "Often" },
] as const;

type Ids<T extends readonly { id: string }[]> = T[number]["id"];
const ids = <T extends readonly { id: string }[]>(list: T) =>
  list.map((item) => item.id) as [Ids<T>, ...Ids<T>[]];

export const profileSchema = z.object({
  preferredTone: z.enum(TONES),
  language: z.enum(ids(LANGUAGES)),
  humour: z.enum(ids(HUMOUR_STYLES)),
  length: z.enum(ids(MESSAGE_LENGTHS)),
  emoji: z.enum(ids(EMOJI_USAGE)),
  writingStyle: z.string().trim().max(300),
  aboutMe: z.string().trim().max(300),
});

export type CommunicationProfile = z.infer<typeof profileSchema>;

export const DEFAULT_PROFILE: CommunicationProfile = {
  preferredTone: "playful",
  language: "match",
  humour: "light",
  length: "short",
  emoji: "rare",
  writingStyle: "",
  aboutMe: "",
};

export function labelFor<T extends readonly { id: string; label: string }[]>(
  list: T,
  id: string,
): string {
  return list.find((item) => item.id === id)?.label ?? id;
}
