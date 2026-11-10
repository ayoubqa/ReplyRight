export const TONES = [
  "flirty",
  "confident",
  "playful",
  "charming",
  "subtle",
] as const;

export type Tone = (typeof TONES)[number];

export interface ToneDefinition {
  id: Tone;
  label: string;
  /** Short line shown in the UI under the tone name. */
  hint: string;
  /** Guidance passed to the model. */
  guidance: string;
}

export const TONE_DEFINITIONS: Record<Tone, ToneDefinition> = {
  flirty: {
    id: "flirty",
    label: "Flirty",
    hint: "Warm, a little bold",
    guidance:
      "Warm and openly interested, with light romantic or teasing energy. Flirt with the person, not at them. Never crude, never pushy.",
  },
  confident: {
    id: "confident",
    label: "Confident",
    hint: "Direct, relaxed, sure",
    guidance:
      "Direct and relaxed. States interest or plans plainly without over-explaining, hedging or seeking approval. Confident is calm, not cocky.",
  },
  playful: {
    id: "playful",
    label: "Playful",
    hint: "Light, teasing, fun",
    guidance:
      "Light-hearted and fun. Gentle teasing, callbacks to what they said, playful exaggeration. Keeps the energy easy and low-stakes.",
  },
  charming: {
    id: "charming",
    label: "Charming",
    hint: "Thoughtful, attentive",
    guidance:
      "Attentive and thoughtful. Picks up on specific details they mentioned, shows genuine curiosity, and makes them feel noticed without flattery overload.",
  },
  subtle: {
    id: "subtle",
    label: "Subtle",
    hint: "Low-key, understated",
    guidance:
      "Understated and low-pressure. Interest is implied rather than declared. Keeps things casual and easy to reply to.",
  },
};

export const INSTRUCTION_SUGGESTIONS = [
  "Make it less eager",
  "Make them laugh",
  "Suggest meeting up",
  "Keep it short",
  "Change the subject",
  "Recover from a dry reply",
] as const;

export const QUICK_TWEAKS = [
  { label: "Shorter", instruction: "Make them noticeably shorter." },
  { label: "Less eager", instruction: "Make it less eager and more relaxed." },
  { label: "Funnier", instruction: "Make them funnier." },
  { label: "Bolder", instruction: "Make them a bit bolder and more direct." },
] as const;
