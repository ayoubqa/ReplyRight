import { z } from "zod";
import { profileSchema } from "./profile";
import { TONES } from "./tones";

export const LIMITS = {
  conversationChars: 6000,
  instructionChars: 200,
  maxImages: 4,
  /** Per image, after client-side compression. */
  maxImageBytes: 4 * 1024 * 1024,
  avoidReplies: 9,
} as const;

export const ACCEPTED_IMAGE_TYPES = [
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/gif",
] as const;
export type AcceptedImageType = (typeof ACCEPTED_IMAGE_TYPES)[number];

/** JSON payload sent alongside optional screenshots (multipart field `payload`). */
export const replyRequestSchema = z.object({
  conversation: z
    .string()
    .trim()
    .max(LIMITS.conversationChars, "That conversation is too long. Paste the last few messages.")
    .default(""),
  tone: z.enum(TONES, { error: "Choose one of the available tones." }),
  instruction: z
    .string()
    .trim()
    .max(LIMITS.instructionChars, "Keep the instruction under 200 characters.")
    .default(""),
  profile: profileSchema.optional(),
  /** Replies already shown, so a regeneration produces genuinely new options. */
  avoid: z.array(z.string().max(1000)).max(LIMITS.avoidReplies).default([]),
});

export type ReplyRequest = z.infer<typeof replyRequestSchema>;

/**
 * Shape the model must return. Kept free of length/count constraints so it is
 * compatible with structured outputs; counts are enforced after parsing.
 */
export const replyResultSchema = z.object({
  read: z.object({
    summary: z
      .string()
      .describe("One or two sentences on where the conversation is and what was last said."),
    vibe: z
      .string()
      .describe("A few words on how the last message comes across, hedged, e.g. 'Reads as relaxed and curious'."),
    cues: z
      .array(z.string())
      .describe("Up to 3 short, concrete hooks from the conversation a reply could build on."),
  }),
  transcript: z
    .array(
      z.object({
        speaker: z.enum(["them", "me", "unknown"]),
        text: z.string(),
      }),
    )
    .describe("Messages read from screenshots, oldest first. Empty array when no screenshots were provided."),
  replies: z
    .array(
      z.object({
        label: z.string().describe("2-4 word name for the approach, e.g. 'Teasing callback'."),
        text: z.string().describe("The message exactly as the user would send it."),
        why: z.string().describe("One short sentence on why this could land."),
      }),
    )
    .describe("Exactly three distinct reply options, or an empty array if declining."),
  headsUp: z
    .string()
    .nullable()
    .describe("A brief, kind note when something deserves care (boundaries, mixed signals, safety). Otherwise null."),
});

export type ReplyResult = z.infer<typeof replyResultSchema>;
export type ReplySuggestion = ReplyResult["replies"][number];

export type GenerationMode = "live" | "demo";

export interface ReplyResponse {
  mode: GenerationMode;
  provider: string;
  model: string | null;
  result: ReplyResult;
}

export type ApiErrorCode =
  | "invalid_request"
  | "unsupported_media"
  | "payload_too_large"
  | "rate_limited"
  | "ai_unavailable"
  | "ai_declined"
  | "ai_bad_output"
  | "internal";

export interface ApiErrorBody {
  error: { code: ApiErrorCode; message: string };
}
