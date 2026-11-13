import "server-only";
import type {
  AcceptedImageType,
  Analysis,
  AnalyzeRequest,
  CoachRequest,
  CoachResult,
  FailureReason,
  GenerationMode,
  RefineRequest,
  RefineResult,
  RepliesRequest,
  RepliesResult,
} from "@/lib/domain/contracts";

/** A screenshot held in memory for the duration of a single request. Never persisted. */
export interface TransientImage {
  mediaType: AcceptedImageType;
  base64: string;
}

export type AiTask = "analyze" | "replies" | "refine" | "coach";
export const AI_TASKS: AiTask[] = ["analyze", "replies", "refine", "coach"];

export interface TaskOptions {
  /** Whether sample messages from My Voice may be used (plan dependent). */
  includeSamples: boolean;
}

/**
 * Provider abstraction for a multimodal LLM. Add a provider by implementing
 * this interface and registering it in `./index.ts`. Routes and clients do not
 * change.
 */
export interface AiProvider {
  readonly id: string;
  readonly mode: GenerationMode;
  readonly supportsImages: boolean;
  modelFor(task: AiTask): string | null;
  analyze(input: { request: AnalyzeRequest; images: TransientImage[] }): Promise<Analysis>;
  replies(input: { request: RepliesRequest; images: TransientImage[]; options: TaskOptions }): Promise<RepliesResult>;
  refine(input: { request: RefineRequest; options: TaskOptions }): Promise<RefineResult>;
  coach(input: { request: CoachRequest; options: TaskOptions }): Promise<CoachResult>;
}

export class ProviderError extends Error {
  /** A coarse cause for diagnostics. Never includes request content. */
  readonly reason: FailureReason;

  constructor(
    public readonly kind: "unavailable" | "declined" | "bad_output" | "rate_limited",
    message: string,
    options?: { cause?: unknown; reason?: FailureReason },
  ) {
    super(message, options?.cause === undefined ? undefined : { cause: options.cause });
    this.name = "ProviderError";
    this.reason = options?.reason ?? "unknown";
  }
}
