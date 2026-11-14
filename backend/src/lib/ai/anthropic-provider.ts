import "server-only";
import Anthropic, { type Middleware } from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { BetaContentBlockParam, BetaMessageParam, BetaUsage } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import type { z } from "zod";
import {
  analysisSchema,
  coachResultSchema,
  LIMITS,
  refineResultSchema,
  repliesResultSchema,
  type Analysis,
  type AnalyzeRequest,
  type CoachRequest,
  type CoachResult,
  type RefineRequest,
  type RefineResult,
  type RepliesRequest,
  type RepliesResult,
} from "@/lib/domain/contracts";
import {
  ANALYZE_SYSTEM,
  buildAnalyzePrompt,
  buildCoachContext,
  buildRefinePrompt,
  buildRepliesPrompt,
  COACH_SYSTEM,
  REFINE_SYSTEM,
  REPLIES_SYSTEM,
} from "./prompts/tasks";
import { serverEnvironment, type ServerEnvironment } from "@/lib/server/environment";
import { checkSpend } from "./budget";
import { recordAiFailure, recordAiSuccess } from "./health";
import { estimateCostUsd } from "./pricing";
import { PRIMARY_ROUTE, routesFromTasks, thinkingParam, type Effort, type RouteTable } from "./router";
import { ProviderError, type AiProvider, type AiTask, type CallContext, type TaskOptions, type TransientImage } from "./types";
import { recordAiUsage, type AiCallStatus } from "./usage-log";

export type { Effort } from "./router";

/** Models that accept the server-side refusal fallback parameter. */
const FALLBACK_MODELS = new Set([
  "claude-opus-5-5",
  "claude-opus-5",
  "claude-sonnet-5-5",
  "claude-fable-5-2",
  "claude-fable-5-1",
]);

export interface AnthropicProviderOptions {
  apiKey: string;
  /** Which model, effort and thinking setting each route uses (`./router.ts`). */
  routes?: RouteTable;
  /** The older form, still used by tests and evals: one model and effort per task, for every route of that task. */
  models?: Record<AiTask, string>;
  efforts?: Record<AiTask, Effort>;
  timeoutMs?: number;
  /** Recorded with every usage record. Defaults to the server's environment. */
  environment?: ServerEnvironment;
  /** Extra attempts after a recoverable failure. Default AI_MAX_RETRIES, or 1. */
  maxRetries?: number;
  /** First backoff delay; it doubles on each retry. Default 500 ms. */
  retryBaseDelayMs?: number;
  /** For tests: replaces the network. */
  fetch?: typeof fetch;
}

/** Backoff never waits longer than this between attempts. */
const MAX_BACKOFF_MS = 4_000;
/** A Retry-After longer than this is not waited out: the user is waiting too. */
const MAX_RETRY_AFTER_MS = 10_000;

/** AI_MAX_RETRIES, 0 to 3. Unset or empty (as in a copied .env.example) means the default, 1. */
export function configuredRetries(): number {
  const raw = process.env.AI_MAX_RETRIES?.trim();
  const value = raw ? Number(raw) : NaN;
  return Number.isInteger(value) && value >= 0 ? Math.min(value, 3) : 1;
}

export interface CallMetrics {
  task: AiTask;
  model: string;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
}

export class AnthropicProvider implements AiProvider {
  readonly id = "anthropic";
  readonly mode = "live" as const;
  readonly supportsImages = true;
  private readonly client: Anthropic;
  private readonly routes: RouteTable;
  /** Optional hook for evals: receives token and latency metrics per call. Never receives content. */
  onMetrics: ((metrics: CallMetrics) => void) | null = null;
  /** Set when the API refuses the optional refusal-fallback parameter, so later calls skip it. */
  private fallbacksRejected = false;
  private readonly environment: ServerEnvironment;
  private readonly maxRetries: number;
  private readonly retryBaseDelayMs: number;

  constructor(options: AnthropicProviderOptions) {
    if (options.routes) {
      this.routes = options.routes;
    } else if (options.models && options.efforts) {
      this.routes = routesFromTasks(options.models, options.efforts);
    } else {
      throw new Error("AnthropicProvider needs routes, or models and efforts per task.");
    }
    this.environment = options.environment ?? serverEnvironment();
    this.maxRetries = options.maxRetries ?? configuredRetries();
    this.retryBaseDelayMs = options.retryBaseDelayMs ?? 500;
    // Retries are handled in `run`, not by the SDK, so each attempt is counted,
    // checked against the spend limit, and never repeated after a timeout (a
    // timed-out answer may already have been billed). The log level is fixed
    // so ANTHROPIC_LOG=debug cannot make the SDK print request bodies.
    this.client = new Anthropic({
      apiKey: options.apiKey,
      timeout: options.timeoutMs ?? 45_000,
      maxRetries: 0,
      logLevel: "warn",
      ...(options.fetch ? { fetch: options.fetch } : {}),
    });
  }

  /** The model of the task's main route, which /status reports. A given request may use another route. */
  modelFor(task: AiTask): string {
    return this.routes[PRIMARY_ROUTE[task]].model;
  }

  async analyze({
    request,
    images,
    call,
  }: {
    request: AnalyzeRequest;
    images: TransientImage[];
    call?: CallContext;
  }): Promise<Analysis> {
    const parsed = await this.run(
      "analyze",
      ANALYZE_SYSTEM,
      analysisSchema,
      [{ role: "user", content: [...imageBlocks(images), { type: "text", text: buildAnalyzePrompt(request, images.length) }] }],
      call,
    );
    return normalizeAnalysis(parsed);
  }

  async replies({
    request,
    images,
    options,
    call,
  }: {
    request: RepliesRequest;
    images: TransientImage[];
    options: TaskOptions;
    call?: CallContext;
  }): Promise<RepliesResult> {
    const parsed = await this.run(
      "replies",
      REPLIES_SYSTEM,
      repliesResultSchema,
      [
        {
          role: "user",
          content: [...imageBlocks(images), { type: "text", text: buildRepliesPrompt(request, images.length, options) }],
        },
      ],
      call,
    );
    return { ...parsed, replies: parsed.replies.slice(0, 3) };
  }

  async refine({
    request,
    options,
    call,
  }: {
    request: RefineRequest;
    options: TaskOptions;
    call?: CallContext;
  }): Promise<RefineResult> {
    const parsed = await this.run(
      "refine",
      REFINE_SYSTEM,
      refineResultSchema,
      [{ role: "user", content: buildRefinePrompt(request, options) }],
      call,
    );
    return { ...parsed, options: parsed.options.slice(0, request.count) };
  }

  async coach({
    request,
    options,
    call,
  }: {
    request: CoachRequest;
    options: TaskOptions;
    call?: CallContext;
  }): Promise<CoachResult> {
    const context = buildCoachContext(request, options);
    const turns: BetaMessageParam[] = request.messages.map((m) => ({
      role: m.role === "user" ? "user" : "assistant",
      content: m.text,
    }));
    // The API needs the exchange to open and close on a user turn. Context opens
    // it; in practice and review mode a closing instruction ends it.
    const messages: BetaMessageParam[] = [];
    if (turns.length > 0 && turns[0].role === "user") {
      messages.push({ role: "user", content: `${context}\n\n${turns[0].content as string}` }, ...turns.slice(1));
    } else {
      messages.push({ role: "user", content: context }, ...turns);
    }
    const closing = coachClosingTurn(request);
    if (messages[messages.length - 1].role === "assistant") {
      messages.push({ role: "user", content: closing ?? "Go on." });
    } else if (closing) {
      const last = messages[messages.length - 1];
      messages[messages.length - 1] = { role: "user", content: `${last.content as string}\n\n${closing}` };
    }

    const parsed = await this.run("coach", COACH_SYSTEM, coachResultSchema, messages, call);
    return {
      ...parsed,
      suggestions: parsed.suggestions.slice(0, 3),
      followUps: parsed.followUps.slice(0, 3),
      review: parsed.review ? { ...parsed.review, improvements: parsed.review.improvements.slice(0, 3) } : null,
      practice: request.mode === "practice" ? parsed.practice : null,
    };
  }

  private async run<Schema extends z.ZodType>(
    task: AiTask,
    system: string,
    schema: Schema,
    messages: BetaMessageParam[],
    call?: CallContext,
  ): Promise<z.infer<Schema>> {
    const route = call?.route ?? PRIMARY_ROUTE[task];
    const policy = this.routes[route];
    const signal = call?.signal;
    const started = Date.now();
    const tracker = new UsageTracker();
    let model = policy.model;
    let usedFallbackModel = false;
    let attempts = 0;
    let retries = 0;

    const record = (status: AiCallStatus, reason: ProviderError["reason"] | null) => {
      const usage = tracker.usage();
      recordAiUsage({
        at: new Date(started).toISOString(),
        environment: this.environment,
        feature: call?.feature ?? task,
        task,
        route,
        client: call?.client ?? "other",
        requestId: call?.requestId ?? null,
        model: policy.model,
        servedModel: tracker.servedModel,
        status,
        reason,
        httpStatus: tracker.httpStatus,
        durationMs: Date.now() - started,
        attempts,
        retries,
        usageKnown: !tracker.unreportedAttempt,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        thinkingTokens: tracker.thinkingTokens,
        cacheReadInputTokens: usage.cacheReadInputTokens,
        cacheCreationInputTokens: usage.cacheWrite5mInputTokens + usage.cacheWrite1hInputTokens,
        estimatedCostUsd: tracker.costUsd(),
        priced: tracker.priced,
      });
      // The response envelope names the model that actually answered.
      if (call && tracker.servedModel) call.servedModel = tracker.servedModel;
    };

    const send = (attemptModel: string, withFallbacks: boolean) => {
      attempts += 1;
      tracker.beginAttempt(attemptModel);
      const thinking = thinkingParam(attemptModel, policy.thinking);
      return this.client.beta.messages.parse(
        {
          model: attemptModel,
          max_tokens: 16000,
          system,
          messages,
          ...(thinking ? { thinking } : {}),
          output_config: { effort: policy.effort, format: betaZodOutputFormat(schema) },
          ...(withFallbacks ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const } : {}),
        },
        { signal, middleware: [tracker.middleware] },
      );
    };

    type Outcome =
      | { kind: "answer"; response: Awaited<ReturnType<typeof send>> }
      /** The API said refusal or max_tokens, but the SDK could not parse the text that came with it. */
      | { kind: "stopped"; stop: "refusal" | "max_tokens" };
    let outcome: Outcome;
    // One try on the route's fallback model, for a model without a server-side
    // refusal fallback of its own (Haiku), and only after a refusal. Errors,
    // timeouts and unusable answers are never re-sent to a bigger model.
    const canUseFallbackModel = () => !usedFallbackModel && policy.fallback !== null && !FALLBACK_MODELS.has(model);
    try {
      for (;;) {
        // Checked before every attempt: retries, the fallback model, every model.
        const spend = checkSpend(new Date(), tracker.costUsd());
        if (!spend.allowed) throw new ProviderError("unavailable", spend.message, { reason: "budget" });
        const useFallbacks = FALLBACK_MODELS.has(model) && !this.fallbacksRejected;
        let response: Awaited<ReturnType<typeof send>>;
        try {
          response = await send(model, useFallbacks);
        } catch (error) {
          if (attemptMayBeBilledUnseen(error)) tracker.unreportedAttempt = true;
          // The SDK parses the text of every answer, so a refusal or a cut-off
          // answer that is not valid JSON surfaces as a parse error. The stop
          // reason from the raw response says what really happened.
          const stop = error instanceof Anthropic.APIError ? null : tracker.attemptStopReason;
          if (stop === "refusal" || stop === "max_tokens") {
            if (stop === "refusal" && canUseFallbackModel()) {
              usedFallbackModel = true;
              model = policy.fallback!;
              continue;
            }
            outcome = { kind: "stopped", stop };
            break;
          }
          // The refusal fallback is an optional extra. If this account, model or
          // platform does not accept the parameter, carry on without it instead
          // of failing every request. This is a different request, not a retry.
          if (useFallbacks && error instanceof Anthropic.BadRequestError && /fallback|beta/i.test(error.message)) {
            this.fallbacksRejected = true;
            console.warn("[replyright] The API did not accept the refusal fallback parameter. Continuing without it.");
            continue;
          }
          const delay = retries < this.maxRetries ? retryDelayMs(error, retries, this.retryBaseDelayMs) : null;
          if (delay === null || signal?.aborted) throw error;
          retries += 1;
          await sleep(delay, signal);
          continue;
        }
        tracker.noteResponse(response.model, response.usage);
        if (response.stop_reason === "refusal" && canUseFallbackModel()) {
          usedFallbackModel = true;
          model = policy.fallback!;
          continue;
        }
        outcome = { kind: "answer", response };
        break;
      }
    } catch (error) {
      const mapped = mapAnthropicError(error);
      recordAiFailure(mapped.reason);
      record(
        mapped.reason === "budget"
          ? "blocked"
          : mapped.reason === "cancelled"
            ? "cancelled"
            : mapped.kind === "bad_output"
              ? "bad_output"
              : "error",
        mapped.reason,
      );
      throw mapped;
    }
    recordAiSuccess();

    const stopReason = outcome.kind === "answer" ? outcome.response.stop_reason : outcome.stop;
    if (outcome.kind === "answer") {
      this.onMetrics?.({
        task,
        model: outcome.response.model,
        latencyMs: Date.now() - started,
        inputTokens: outcome.response.usage.input_tokens,
        outputTokens: outcome.response.usage.output_tokens,
      });
    }

    if (stopReason === "refusal") {
      record("refused", "refusal");
      throw new ProviderError("declined", "I can't help with this one. Try sharing a different part of the conversation.", {
        reason: "refusal",
      });
    }
    if (stopReason === "max_tokens" || outcome.kind !== "answer") {
      record("cut_off", "output");
      throw new ProviderError("bad_output", "That answer got cut short. Please try again.", { reason: "output" });
    }
    const response = outcome.response;
    const parsed = response.parsed_output;
    if (!parsed) {
      record("bad_output", "output");
      throw new ProviderError("bad_output", "Something came back garbled. Please try again.", { reason: "output" });
    }
    record("ok", null);
    return parsed as z.infer<Schema>;
  }
}

/**
 * Collects token usage from every HTTP attempt of one call, and prices each
 * answer by the model that produced it (a refusal on Haiku and the Sonnet
 * answer after it are priced separately). It reads usage through SDK
 * middleware, so a billed answer that later fails to parse is still counted.
 * It keeps numbers only.
 */
class UsageTracker {
  private input = 0;
  private output = 0;
  private cacheRead = 0;
  private cacheWrite5m = 0;
  private cacheWrite1h = 0;
  private cost = 0;
  private attemptModel = "";
  private attemptReported = false;
  /** The stop reason of the current attempt's response, read before the SDK parses its text. */
  attemptStopReason: string | null = null;
  priced = true;
  thinkingTokens: number | null = null;
  servedModel: string | null = null;
  httpStatus: number | null = null;
  /** An attempt ended without a response that reports usage, but may still have been billed. */
  unreportedAttempt = false;

  readonly middleware: Middleware = async (request, next, context) => {
    const response = await next(request);
    this.httpStatus = response.status;
    if (response.ok) {
      try {
        const body = await context.parse<{ model?: unknown; usage?: BetaUsage | null; stop_reason?: unknown }>(response);
        this.attemptStopReason = typeof body?.stop_reason === "string" ? body.stop_reason : null;
        this.add(typeof body?.model === "string" ? body.model : null, body?.usage ?? null);
      } catch {
        // Not a message body. Usage is taken from the parsed response instead, when there is one.
      }
    }
    return response;
  };

  beginAttempt(model: string) {
    this.attemptModel = model;
    this.attemptReported = false;
    this.attemptStopReason = null;
  }

  /** Called with each parsed response. Counts it only if the middleware did not (as in unit tests). */
  noteResponse(model: string, usage: BetaUsage | null | undefined) {
    if (!this.attemptReported) this.add(model, usage ?? null);
  }

  private add(model: string | null, usage: BetaUsage | null) {
    if (model) this.servedModel = model;
    if (!usage) return;
    this.attemptReported = true;
    const tokens = {
      inputTokens: usage.input_tokens ?? 0,
      outputTokens: usage.output_tokens ?? 0,
      cacheReadInputTokens: usage.cache_read_input_tokens ?? 0,
      cacheWrite5mInputTokens: usage.cache_creation
        ? (usage.cache_creation.ephemeral_5m_input_tokens ?? 0)
        : (usage.cache_creation_input_tokens ?? 0),
      cacheWrite1hInputTokens: usage.cache_creation?.ephemeral_1h_input_tokens ?? 0,
    };
    this.input += tokens.inputTokens;
    this.output += tokens.outputTokens;
    this.cacheRead += tokens.cacheReadInputTokens;
    this.cacheWrite5m += tokens.cacheWrite5mInputTokens;
    this.cacheWrite1h += tokens.cacheWrite1hInputTokens;
    const estimate = estimateCostUsd(model ?? this.attemptModel, tokens);
    this.cost += estimate.costUsd;
    this.priced &&= estimate.priced;
    const thinking = usage.output_tokens_details?.thinking_tokens;
    if (typeof thinking === "number") this.thinkingTokens = (this.thinkingTokens ?? 0) + thinking;
  }

  costUsd(): number {
    return Math.round(this.cost * 1_000_000) / 1_000_000;
  }

  usage() {
    return {
      inputTokens: this.input,
      outputTokens: this.output,
      cacheReadInputTokens: this.cacheRead,
      cacheWrite5mInputTokens: this.cacheWrite5m,
      cacheWrite1hInputTokens: this.cacheWrite1h,
    };
  }
}

/** Timeouts, cancellations and dropped connections can be billed without a response to read usage from. */
function attemptMayBeBilledUnseen(error: unknown): boolean {
  return error instanceof Anthropic.APIConnectionError || error instanceof Anthropic.APIUserAbortError;
}

/**
 * How long to wait before trying again, or null when the error must not be
 * retried. Retried: overload and server errors (5xx), rate limits (429),
 * request timeouts and lock conflicts reported by the API (408, 409), and
 * failures to connect. Never retried: our own timeouts (the answer may already
 * have been billed), cancellations, refusals, unusable output, and every other
 * 4xx, which would fail the same way again. The API's x-should-retry header
 * wins when present, as it does in the SDK.
 */
export function retryDelayMs(error: unknown, retry: number, baseDelayMs: number): number | null {
  if (error instanceof Anthropic.APIConnectionTimeoutError || error instanceof Anthropic.APIUserAbortError) return null;
  let headers: Headers | undefined;
  let retryable = false;
  if (error instanceof Anthropic.APIConnectionError) {
    retryable = true;
  } else if (error instanceof Anthropic.APIError && typeof error.status === "number") {
    headers = error.headers as Headers | undefined;
    const hint = headers?.get("x-should-retry");
    if (hint === "false") return null;
    retryable = hint === "true" || error.status === 408 || error.status === 409 || error.status === 429 || error.status >= 500;
  }
  if (!retryable) return null;

  const asked = retryAfterMs(headers);
  if (asked !== null) return asked <= MAX_RETRY_AFTER_MS ? asked : null;
  const backoff = Math.min(MAX_BACKOFF_MS, baseDelayMs * 2 ** retry);
  // Jitter keeps many clients from retrying in step.
  return Math.round(backoff * (0.8 + Math.random() * 0.2));
}

function retryAfterMs(headers: Headers | undefined): number | null {
  if (!headers) return null;
  const ms = Number(headers.get("retry-after-ms"));
  if (headers.get("retry-after-ms") && Number.isFinite(ms) && ms >= 0) return ms;
  const raw = headers.get("retry-after");
  if (!raw) return null;
  const seconds = Number(raw);
  if (Number.isFinite(seconds) && seconds >= 0) return seconds * 1000;
  const date = Date.parse(raw);
  return Number.isNaN(date) ? null : Math.max(0, date - Date.now());
}

function cancelled(): ProviderError {
  return new ProviderError("unavailable", "The request was cancelled.", { reason: "cancelled" });
}

/** Waits between attempts, and stops at once if the caller goes away. */
function sleep(ms: number, signal: AbortSignal | undefined): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(cancelled());
      return;
    }
    const onAbort = () => {
      clearTimeout(timer);
      reject(cancelled());
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}

/** The instruction that closes a coaching exchange, depending on the mode. */
function coachClosingTurn(request: CoachRequest): string | null {
  if (request.mode === "review") {
    return "Look at my message and coach me on it. Fill in review.";
  }
  if (request.mode === "practice") {
    return request.messages.length === 0
      ? "Set up the practice. Tell me briefly who you are playing and what the situation is, then either send their first message or ask me to send mine."
      : "Stay in the practice: give me feedback on what I just sent, then answer as them.";
  }
  return null;
}

/**
 * Screenshots as image content blocks, in the order the user attached them.
 * They come before the text that refers to them, as the API recommends.
 */
export function imageBlocks(images: TransientImage[]): BetaContentBlockParam[] {
  return images.map(
    (image): BetaContentBlockParam => ({
      type: "image",
      source: { type: "base64", media_type: image.mediaType, data: image.base64 },
    }),
  );
}

const clean = (text: string) => text.replace(/\s+/g, " ").trim();

/**
 * Makes the analysis consistent before it reaches the app. Structured output
 * guarantees the shape; this enforces what the schema cannot express.
 *
 * It removes and trims, and it refuses an answer with nothing to show. It never
 * adds content the model did not write.
 */
export function normalizeAnalysis(parsed: Analysis): Analysis {
  const read = parsed.read.trim();
  if (!read) {
    throw new ProviderError("bad_output", "Something came back garbled. Please try again.", { reason: "output" });
  }
  const transcript = parsed.transcript
    .map((line) => ({ speaker: line.speaker, text: line.text.trim().slice(0, LIMITS.transcriptLineChars) }))
    .filter((line) => line.text.length > 0)
    .slice(-LIMITS.transcriptLines);
  const latestMessage = parsed.latestMessage?.trim() || null;
  // Nothing can be answered from a screenshot that could not be read, or from something that is not a conversation.
  const unusable = parsed.problem === "unreadable" || parsed.problem === "not_a_conversation";
  return {
    ...parsed,
    canReply: parsed.canReply && !unusable,
    read,
    transcript,
    latestMessage,
    toneLabel: clean(parsed.toneLabel),
    observations: parsed.observations.map(clean).filter(Boolean).slice(0, 4),
    assumptions: parsed.assumptions.map(clean).filter(Boolean).slice(0, 3),
    opportunity: parsed.opportunity.trim(),
    suggestedIntents: [...new Set(parsed.suggestedIntents)].slice(0, 3),
    headsUp: parsed.headsUp?.trim() || null,
  };
}

/** True when the API refused the request because of an image in it. */
function isImageRejection(error: InstanceType<typeof Anthropic.BadRequestError>): boolean {
  return /\bimage\b|media_type|base64/i.test(error.message);
}

/**
 * Whether the provider's own error text may be written to the server log.
 * It describes parameters, not conversations, but it stays out of production
 * logs unless someone asks for it with RR_DEBUG_ERRORS=true.
 */
function logsProviderMessages(): boolean {
  const flag = process.env.RR_DEBUG_ERRORS?.trim().toLowerCase();
  if (flag === "true" || flag === "1") return true;
  if (flag === "false" || flag === "0") return false;
  return process.env.NODE_ENV !== "production";
}

function describe(error: InstanceType<typeof Anthropic.APIError>): string {
  const parts = [`status ${error.status ?? "none"}`];
  if (error.requestID) parts.push(`request ${error.requestID}`);
  if (logsProviderMessages()) parts.push(error.message.slice(0, 300));
  return parts.join(", ");
}

/**
 * Maps SDK errors to typed provider errors with a coarse reason for
 * diagnostics. Logs status and request id, never request content.
 */
function mapAnthropicError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  if (error instanceof Anthropic.APIUserAbortError) return cancelled();
  const notSetUp = "ReplyRight isn't set up correctly on our side. Please try again later.";

  if (error instanceof Anthropic.RateLimitError) {
    console.error(`[replyright] Anthropic rate limit (${describe(error)}).`);
    return new ProviderError("rate_limited", "Things are busy right now. Give it a moment and try again.", {
      cause: error,
      reason: "rate_limit",
    });
  }
  if (error instanceof Anthropic.AuthenticationError) {
    console.error(
      `[replyright] Anthropic rejected the API key (${describe(error)}). Check ${serverEnvironment() === "production" ? "ANTHROPIC_API_KEY" : "ANTHROPIC_API_KEY_DEV"}.`,
    );
    return new ProviderError("unavailable", notSetUp, { cause: error, reason: "credentials" });
  }
  if (error instanceof Anthropic.PermissionDeniedError) {
    console.error(`[replyright] The API key may not use this model or feature (${describe(error)}).`);
    return new ProviderError("unavailable", notSetUp, { cause: error, reason: "credentials" });
  }
  if (error instanceof Anthropic.NotFoundError) {
    console.error(`[replyright] Anthropic does not know the configured model (${describe(error)}). Check AI_MODEL.`);
    return new ProviderError("unavailable", notSetUp, { cause: error, reason: "model" });
  }
  if (error instanceof Anthropic.BadRequestError) {
    if (/credit balance|billing/i.test(error.message)) {
      console.error(`[replyright] The Anthropic account has no credit (${describe(error)}).`);
      return new ProviderError("unavailable", notSetUp, { cause: error, reason: "billing" });
    }
    if (isImageRejection(error)) {
      // Images are fully decoded and normalised before they are sent, so this
      // should be rare. The message names the field, never the image content.
      console.error(`[replyright] Anthropic could not use an image (${describe(error)}).`);
      return new ProviderError(
        "rejected_input",
        "I couldn't read one of those screenshots. Try taking it again, or paste the text instead.",
        { cause: error, reason: "image" },
      );
    }
    console.error(`[replyright] Anthropic rejected the request (${describe(error)}).`);
    return new ProviderError("misconfigured", "Something went wrong on our side. Please try again.", {
      cause: error,
      reason: "request",
    });
  }
  // The timeout error is a kind of connection error, so it is checked first.
  if (error instanceof Anthropic.APIConnectionTimeoutError) {
    console.error("[replyright] The AI provider took too long to answer.");
    return new ProviderError("unavailable", "That took longer than it should. Please try again.", {
      cause: error,
      reason: "timeout",
    });
  }
  if (error instanceof Anthropic.APIConnectionError) {
    console.error("[replyright] The server could not connect to the AI provider.");
    return new ProviderError("unavailable", "I couldn't reach the writing service. Please try again.", {
      cause: error,
      reason: "network",
    });
  }
  if (error instanceof Anthropic.InternalServerError) {
    console.error(`[replyright] The AI provider is having trouble (${describe(error)}).`);
    return new ProviderError("unavailable", "The writing service is busy right now. Please try again.", {
      cause: error,
      reason: "overloaded",
    });
  }
  if (error instanceof Anthropic.APIError) {
    console.error(`[replyright] Anthropic API error (${describe(error)}).`);
    return new ProviderError("unavailable", "Something went wrong on our side. Please try again.", { cause: error });
  }
  // Output that failed schema validation surfaces as a parse error from the SDK helper.
  console.error("[replyright] Unexpected AI error:", error instanceof Error ? error.name : "unknown");
  return new ProviderError("bad_output", "Something came back garbled. Please try again.", {
    cause: error,
    reason: "output",
  });
}
