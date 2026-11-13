/**
 * Intents: what the user wants their message to achieve.
 * IDs are part of the API contract and mirrored in the iOS app
 * (ios/Packages/ReplyRightKit/Sources/ReplyRightCore/Models/Intent.swift).
 */
export const INTENTS = [
  "natural",
  "flirt",
  "laugh",
  "interest",
  "confident",
  "keep_going",
  "mysterious",
  "charming",
  "ask_out",
  "dry_reply",
  "feelings",
  "boundary",
] as const;

export type Intent = (typeof INTENTS)[number];

export interface IntentDefinition {
  id: Intent;
  label: string;
  /** Guidance passed to the model. */
  guidance: string;
}

export const INTENT_DEFINITIONS: Record<Intent, IntentDefinition> = {
  natural: {
    id: "natural",
    label: "Just help me reply",
    guidance:
      "No special agenda. Write what a relaxed, likeable version of the user would send: responsive to what was said, easy to reply to.",
  },
  flirt: {
    id: "flirt",
    label: "Flirt naturally",
    guidance:
      "Warm, openly interested, a little teasing. Flirt with the person, not at them. It should feel like chemistry, never a line. Never crude or pushy.",
  },
  laugh: {
    id: "laugh",
    label: "Make them laugh",
    guidance:
      "Aim for a real smile: a playful observation, a callback to something they said, gentle exaggeration. Humour that includes them, never humour at their expense.",
  },
  interest: {
    id: "interest",
    label: "Show interest",
    guidance:
      "Make it clear the user is genuinely curious about them. Pick up a specific detail and build on it. Interested, not interrogating.",
  },
  confident: {
    id: "confident",
    label: "Sound confident",
    guidance:
      "Calm and direct. Says what the user means without over-explaining, hedging or asking for approval. Confident is relaxed, not cocky or arrogant.",
  },
  keep_going: {
    id: "keep_going",
    label: "Keep the conversation going",
    guidance:
      "Give the other person something easy and interesting to respond to: a light question, a thread to pull, a small opinion to react to.",
  },
  mysterious: {
    id: "mysterious",
    label: "Be a little mysterious",
    guidance:
      "Leave something unsaid in a playful way that invites curiosity. Intriguing, not evasive. Never dishonest, cold or game-playing.",
  },
  charming: {
    id: "charming",
    label: "Give a charming response",
    guidance:
      "Attentive and thoughtful with a light touch. Notices a detail, makes them feel seen, without flattery overload.",
  },
  ask_out: {
    id: "ask_out",
    label: "Move towards asking them out",
    guidance:
      "Move from chatting towards meeting. Prefer a specific, low-pressure suggestion that grows out of the conversation and is easy to say yes or no to. If the moment isn't there yet, offer a reply that builds towards it and say so in the note.",
  },
  dry_reply: {
    id: "dry_reply",
    label: "Respond to a dry message",
    guidance:
      "Their last message was short or flat. Re-energise the conversation without chasing or calling them out: change the angle, add something fun, or keep it brief and unbothered. One short reply is not proof of disinterest.",
  },
  feelings: {
    id: "feelings",
    label: "Express my feelings",
    guidance:
      "Help the user say how they feel honestly and simply. Sincere and specific, without pressure or expectation of a matching answer. Vulnerable, not heavy.",
  },
  boundary: {
    id: "boundary",
    label: "Set a boundary respectfully",
    guidance:
      "Help the user say what they are or are not comfortable with. Clear, kind and firm, with no apologising for having a boundary and no blaming. Flirtation is optional here; clarity comes first.",
  },
};

/** Intents available on the free plan by default. Override with FREE_INTENTS. */
export const DEFAULT_FREE_INTENTS: Intent[] = ["natural", "flirt", "laugh", "interest", "keep_going", "boundary"];

export function isIntent(value: string): value is Intent {
  return (INTENTS as readonly string[]).includes(value);
}
