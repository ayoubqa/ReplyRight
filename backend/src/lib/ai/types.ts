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
import type { RouteKey } from "./router";

/**
 * A screenshot held in memory for the duration of a single request. Never
 * persisted. It has been fully decoded on the server, so the bytes are a valid
 * image of `mediaType`, upright and within the provider's limits.
 */
export interface TransientImage {
  mediaType: AcceptedImageType;
  base64: string;
  width: number;
  height: number;
}

export type AiTask = "analyze" | "replies" | "refine" | "coach";
export const AI_TASKS: AiTask[] = ["analyze", "replies", "refine", "coach"];

export interface TaskOptions {
  /** Whether sample messages from My Voice may be used (plan dependent). */
  includeSamples: boolean;
}

/**
 * Bookkeeping for one AI call. None of it reaches the model.
 */
export interface CallContext {
  /** What the call is for, as recorded in the usage ledger. Defaults to the task name. */
  feature?: string;
  /** The server's request id, so a usage record can be matched to the request log line. */
  requestId?: string;
  /** Which client asked: app, keyboard, share, diagnostics or other. */
  client?: string;
  /** Which route (model policy) serves the call. Defaults to the task's main route. */
  route?: RouteKey;
  /** Set by the provider: the model that actually answered. */
  servedModel?: string;
  /** Stops the call, for example when the app that asked for it has gone away. */
  signal?: AbortSignal;
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
  analyze(input: { request: AnalyzeRequest; images: TransientImage[]; call?: CallContext }): Promise<Analysis>;
  replies(input: {
    request: RepliesRequest;
    images: TransientImage[];
    options: TaskOptions;
    call?: CallContext;
  }): Promise<RepliesResult>;
  refine(input: { request: RefineRequest; options: TaskOptions; call?: CallContext }): Promise<RefineResult>;
  coach(input: { request: CoachRequest; options: TaskOptions; call?: CallContext }): Promise<CoachResult>;
}

export class ProviderError extends Error {
  /** A coarse cause for diagnostics. Never includes request content. */
  readonly reason: FailureReason;

  constructor(
    /**
     * unavailable     the provider cannot answer right now (safe to retry)
     * declined        the model refused this content
     * bad_output      the model's answer was unusable (cut short, or not in the expected shape)
     * rejected_input  the provider refused something the user sent, such as an image it cannot read
     * misconfigured   the provider refused the request itself: a server bug or setting, not the user's fault
     * rate_limited    too many requests
     */
    public readonly kind: "unavailable" | "declined" | "bad_output" | "rejected_input" | "misconfigured" | "rate_limited",
    message: string,
    options?: { cause?: unknown; reason?: FailureReason },
  ) {
    super(message, options?.cause === undefined ? undefined : { cause: options.cause });
    this.name = "ProviderError";
    this.reason = options?.reason ?? "unknown";
  }
}
