import { z } from "zod";
import { INTENTS } from "./intents";
import { crushSchema, voiceSchema } from "./voice";

/**
 * API v1 contract. Request schemas validate what clients send; result schemas
 * are the structured output the model must return. The iOS app mirrors these
 * in ReplyRightCore/Models/API.swift. Change both sides together.
 */
export const LIMITS = {
  conversationChars: 6000,
  transcriptLines: 80,
  transcriptLineChars: 1000,
  instructionChars: 200,
  situationChars: 600,
  draftChars: 1000,
  maxImages: 4,
  /** Per image, after on-device compression. */
  maxImageBytes: 4 * 1024 * 1024,
  avoidReplies: 9,
  coachMessages: 24,
  coachMessageChars: 1500,
} as const;

export const ACCEPTED_IMAGE_TYPES = ["image/png", "image/jpeg", "image/webp", "image/gif"] as const;
export type AcceptedImageType = (typeof ACCEPTED_IMAGE_TYPES)[number];

const speaker = z.enum(["them", "me", "unknown"]);
export const transcriptLineSchema = z.object({
  speaker,
  text: z.string().trim().min(1).max(LIMITS.transcriptLineChars),
});
export type TranscriptLine = z.infer<typeof transcriptLineSchema>;

const conversation = z
  .string()
  .trim()
  .max(LIMITS.conversationChars, "That conversation is too long. Share just the last few messages.")
  .default("");
const instruction = z
  .string()
  .trim()
  .max(LIMITS.instructionChars, "Keep the instruction under 200 characters.")
  .default("");
/** Language for explanations shown in the app UI (not for the replies themselves). */
const locale = z.string().trim().max(12).default("en");

const shared = {
  voice: voiceSchema.optional(),
  crush: crushSchema.optional(),
  locale,
};

// ---------------------------------------------------------------- analyze

export const analyzeRequestSchema = z.object({
  conversation,
  ...shared,
});
export type AnalyzeRequest = z.infer<typeof analyzeRequestSchema>;

/**
 * Whether the shared material could be read.
 *   none                everything was readable
 *   partly_readable     some of it was cut off, blurry or too small; only the readable part was transcribed
 *   unreadable          the screenshot is too blurry, dark, cropped or small to read
 *   not_a_conversation  readable, but not a messaging conversation
 */
export const ANALYSIS_PROBLEMS = ["none", "partly_readable", "unreadable", "not_a_conversation"] as const;
export type AnalysisProblem = (typeof ANALYSIS_PROBLEMS)[number];

export const analysisSchema = z.object({
  canReply: z
    .boolean()
    .describe("False when there is no conversation to reply to, it is unreadable, or replying would be inappropriate."),
  transcript: z
    .array(z.object({ speaker, text: z.string() }))
    .describe("The messages, oldest first, in their original language."),
  latestMessage: z
    .string()
    .nullable()
    .describe("The most recent message from the other person that a reply would answer, verbatim. Null if none."),
  latestFromMe: z.boolean().describe("True when the user sent the most recent message in the conversation."),
  read: z
    .string()
    .describe("One or two friendly sentences on what seems to be going on, hedged, like a perceptive friend would say it."),
  toneLabel: z.string().describe("2-4 words for the conversational tone, e.g. 'Playful teasing'."),
  observations: z.array(z.string()).describe("2-4 things that are plainly visible in the messages. Facts, not interpretation."),
  assumptions: z
    .array(z.string())
    .describe("1-3 possibilities that cannot be known from the messages, each clearly hedged."),
  opportunity: z.string().describe("One sentence on a good angle for the next message."),
  suggestedIntents: z.array(z.enum(INTENTS)).describe("2-3 intent ids that fit this moment, best first."),
  headsUp: z.string().nullable().describe("A brief, kind note when something deserves care. Otherwise null."),
  problem: z
    .enum(ANALYSIS_PROBLEMS)
    .describe("Whether the shared screenshots or text could be read. Use none when everything was readable."),
});
export type Analysis = z.infer<typeof analysisSchema>;

// ---------------------------------------------------------------- replies

export const repliesRequestSchema = z.object({
  /** "reply" answers a conversation; "starter" opens one (or restarts it). */
  kind: z.enum(["reply", "starter"]).default("reply"),
  conversation,
  /** Structured transcript from a previous /analyze call (preferred over raw text). */
  transcript: z.array(transcriptLineSchema).max(LIMITS.transcriptLines).default([]),
  /** For starters: where they know the person from, what they know about them. */
  situation: z.string().trim().max(LIMITS.situationChars).default(""),
  intent: z.enum(INTENTS, { error: "Choose one of the available intentions." }).default("natural"),
  instruction,
  /** What the user has typed so far (keyboard). Treated as direction, not as final text. */
  draft: z.string().trim().max(LIMITS.draftChars).default(""),
  /** Replies already shown, so regenerating produces genuinely new options. */
  avoid: z.array(z.string().max(1000)).max(LIMITS.avoidReplies).default([]),
  ...shared,
});
export type RepliesRequest = z.infer<typeof repliesRequestSchema>;

export const suggestionSchema = z.object({
  style: z.string().describe("2-3 words naming this option's communication style, e.g. 'Most natural', 'Playful', 'More direct'."),
  text: z.string().describe("The message exactly as the user would send it."),
  why: z.string().describe("One short, plain sentence on why this could work."),
});
export type Suggestion = z.infer<typeof suggestionSchema>;

export const repliesResultSchema = z.object({
  note: z
    .string()
    .describe("One short, warm line to show above the options, like a friend handing over ideas. No hype, no promises."),
  replies: z.array(suggestionSchema).describe("Exactly three options with distinct purposes, or an empty array if declining."),
  headsUp: z.string().nullable().describe("A brief, kind note when something deserves care. Otherwise null."),
});
export type RepliesResult = z.infer<typeof repliesResultSchema>;

// ---------------------------------------------------------------- refine

export const REFINE_ACTIONS = [
  "shorter",
  "funnier",
  "more_romantic",
  "more_confident",
  "less_intense",
  "more_natural",
  "more_like_me",
  "flirty",
  "playful",
  "charming",
  "subtle",
  "warm",
  "more_direct",
  "ask_question",
  "keep_going",
] as const;
export type RefineAction = (typeof REFINE_ACTIONS)[number];

export const refineRequestSchema = z.object({
  text: z.string().trim().min(1, "There's nothing to rewrite yet.").max(LIMITS.draftChars),
  action: z.enum(REFINE_ACTIONS, { error: "Choose one of the available rewrites." }),
  instruction,
  /** 1 replaces a single card; 3 offers alternatives (keyboard, draft polish). */
  count: z.union([z.literal(1), z.literal(3)]).default(1),
  conversation,
  ...shared,
});
export type RefineRequest = z.infer<typeof refineRequestSchema>;

export const refineResultSchema = z.object({
  options: z.array(suggestionSchema).describe("The rewritten message(s). Exactly as many as requested."),
  note: z.string().nullable().describe("One short line on what changed, or null."),
});
export type RefineResult = z.infer<typeof refineResultSchema>;

// ---------------------------------------------------------------- coach

export const coachMessageSchema = z.object({
  role: z.enum(["user", "coach"]),
  text: z.string().trim().min(1).max(LIMITS.coachMessageChars),
});

/**
 * ask      a question to the coach, optionally about a draft or a conversation
 * review   feedback on one message the user wrote or plans to send
 * practice a rehearsal: the coach plays the other person and gives feedback
 */
export const COACH_MODES = ["ask", "review", "practice"] as const;
export type CoachMode = (typeof COACH_MODES)[number];

export const COACH_TOPICS = ["general", "flirting", "conversation", "asking_out", "confidence"] as const;
export type CoachTopic = (typeof COACH_TOPICS)[number];

export const PRACTICE_SCENARIOS = [
  "first_message",
  "keep_it_going",
  "flirting",
  "asking_out",
  "reconnecting",
  "boundary",
  "custom",
] as const;
export type PracticeScenario = (typeof PRACTICE_SCENARIOS)[number];

export const coachRequestSchema = z.object({
  mode: z.enum(COACH_MODES).default("ask"),
  topic: z.enum(COACH_TOPICS).default("general"),
  /**
   * ask: the running chat with the coach, ending on the user's question.
   * practice: the rehearsal so far. "user" is what the user sent, "coach" is
   * what the simulated person answered. Empty on the opening turn.
   */
  messages: z.array(coachMessageSchema).max(LIMITS.coachMessages).default([]),
  conversation,
  /** A message the user wrote or is thinking of sending. Required for review. */
  draft: z.string().trim().max(LIMITS.draftChars).default(""),
  /** Review: what the user wants the message to get across. */
  goal: z.string().trim().max(LIMITS.instructionChars).default(""),
  /** Practice: the situation being rehearsed. */
  scenario: z
    .object({
      id: z.enum(PRACTICE_SCENARIOS),
      detail: z.string().trim().max(300).default(""),
    })
    .optional(),
  ...shared,
});
export type CoachRequest = z.infer<typeof coachRequestSchema>;

export const REVIEW_ASPECTS = ["natural", "intensity", "formality", "feeling", "clarity"] as const;
export const REVIEW_VERDICTS = ["good", "watch", "rework"] as const;

export const coachReviewSchema = z.object({
  intent: z.string().describe("What the user is trying to communicate, in one plain sentence."),
  comesAcross: z
    .string()
    .describe("What the message as written communicates: how it could read to the person receiving it. Hedged, never a claim about what they will think."),
  checks: z
    .array(
      z.object({
        aspect: z.enum(REVIEW_ASPECTS),
        verdict: z.enum(REVIEW_VERDICTS),
        note: z.string().describe("One short sentence explaining the verdict, pointing at the words that cause it."),
      }),
    )
    .describe(
      "One entry per aspect, in this order: natural (does it sound like a real text), intensity (too much, too eager), formality (too stiff), feeling (does it carry the feeling they intend), clarity (could it be misunderstood).",
    ),
  improvements: z.array(z.string()).describe("0-3 concrete things that could be better. Empty when the message is already good."),
  alternative: z
    .string()
    .describe("A suggested alternative, exactly as it would be sent. When the original is already good, return it unchanged or nearly unchanged."),
  whyItWorks: z.string().describe("One or two sentences on why the alternative works."),
  lesson: z.string().describe("One small, transferable lesson the user can reuse next time."),
});
export type CoachReview = z.infer<typeof coachReviewSchema>;

export const coachPracticeSchema = z.object({
  partnerReply: z
    .string()
    .nullable()
    .describe("The simulated person's next message, written as a text. Null when the user should send the first message, or when the practice has ended."),
  feedback: z
    .string()
    .nullable()
    .describe("Coaching on the user's latest practice message: what worked and one thing to try. Null on the opening turn."),
  tryThis: z.string().nullable().describe("One line the user could try next, or null."),
  finished: z.boolean().describe("True when the rehearsal has reached a natural end."),
});
export type CoachPractice = z.infer<typeof coachPracticeSchema>;

export const coachResultSchema = z.object({
  message: z.string().describe("The coach's words to the user: practical, warm, a few short paragraphs at most. Plain text, no markdown."),
  suggestions: z
    .array(z.object({ label: z.string(), text: z.string() }))
    .describe("0-3 ready-to-send lines when wording would help, each with a 2-3 word label."),
  followUps: z.array(z.string()).describe("2-3 short questions the user might want to ask next, written in their voice."),
  lesson: z.string().nullable().describe("One small takeaway worth remembering, or null when nothing new was taught."),
  review: coachReviewSchema.nullable().describe("Filled whenever the user shared a message of their own to look at. Otherwise null."),
  practice: coachPracticeSchema.nullable().describe("Filled in practice mode. Otherwise null."),
  headsUp: z.string().nullable(),
});
export type CoachResult = z.infer<typeof coachResultSchema>;

// ---------------------------------------------------------------- envelope

export type GenerationMode = "live" | "demo";
export type Tier = "free" | "pro";

export interface UsageSnapshot {
  tier: Tier;
  generations: { used: number; limit: number; remaining: number };
  coach: { used: number; limit: number; remaining: number };
  /** ISO timestamp when daily counters reset. */
  resetsAt: string;
}

export interface Envelope<T> {
  mode: GenerationMode;
  provider: string;
  model: string | null;
  usage: UsageSnapshot;
  result: T;
}

export type ApiErrorCode =
  | "invalid_request"
  | "unsupported_media"
  | "payload_too_large"
  | "rate_limited"
  | "limit_reached"
  | "upgrade_required"
  | "ai_unavailable"
  | "ai_declined"
  | "ai_bad_output"
  | "internal";

/**
 * Why an AI call failed, in terms that help whoever runs the server. Shown in
 * the app's connection diagnostics. Never contains request content or secrets.
 */
export type FailureReason =
  | "credentials"
  | "billing"
  | "model"
  | "request"
  | "overloaded"
  | "timeout"
  | "network"
  | "rate_limit"
  | "refusal"
  | "output"
  | "image"
  | "unknown";

export interface ApiErrorBody {
  error: { code: ApiErrorCode; message: string; usage?: UsageSnapshot; reason?: FailureReason; requestId?: string };
}

/** What the server knows about its AI provider since it started. No secrets. */
export interface AiHealth {
  state: "untested" | "ok" | "failing";
  lastSuccessAt: string | null;
  lastFailureAt: string | null;
  lastFailureReason: FailureReason | null;
}
