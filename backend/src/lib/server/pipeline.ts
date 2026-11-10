import "server-only";
import type { z } from "zod";
import { getProvider, ProviderError, type AiProvider, type AiTask } from "@/lib/ai";
import type { TransientImage } from "@/lib/ai/types";
import type { ApiErrorBody, ApiErrorCode, Envelope, Tier, UsageSnapshot } from "@/lib/domain/contracts";
import { resolveTier } from "./entitlements";
import { InputError, readTransientImages } from "./images";
import { getPlans, type Plan } from "./plans";
import { checkRateLimit, clientKey } from "./rate-limit";
import { consumeUsage, refundUsage, usageSnapshot, usageSubject, type Meter } from "./usage";

const NO_STORE = { "Cache-Control": "no-store" };

export function errorResponse(
  status: number,
  code: ApiErrorCode,
  message: string,
  extra?: { usage?: UsageSnapshot; headers?: HeadersInit },
) {
  const body: ApiErrorBody = { error: { code, message, ...(extra?.usage ? { usage: extra.usage } : {}) } };
  return Response.json(body, { status, headers: { ...NO_STORE, ...extra?.headers } });
}

/** A plan restriction: the request is valid but needs Pro. */
export class UpgradeRequired extends Error {}

export interface TaskContext<Input> {
  input: Input;
  images: TransientImage[];
  tier: Tier;
  plan: Plan;
  provider: AiProvider;
}

interface TaskConfig<Schema extends z.ZodType, Result> {
  task: AiTask;
  schema: Schema;
  /** Whether screenshots may accompany the request (multipart). */
  allowImages?: boolean;
  /** Which daily counter this request draws from. */
  meter: Meter | null;
  /** Extra validation beyond the schema. Return a message to reject with 400. */
  validate?: (input: z.infer<Schema>, images: TransientImage[]) => string | null;
  /** Plan gating. Throw UpgradeRequired to reject with 402. */
  gate?: (context: TaskContext<z.infer<Schema>>) => void;
  run: (context: TaskContext<z.infer<Schema>>) => Promise<Result>;
}

async function readBody(request: Request): Promise<{ payload: unknown; files: File[] } | Response> {
  const contentType = request.headers.get("content-type") ?? "";
  try {
    if (contentType.includes("multipart/form-data")) {
      const form = await request.formData();
      const raw = form.get("payload");
      const payload = typeof raw === "string" ? JSON.parse(raw) : null;
      const files = form.getAll("images").filter((value): value is File => value instanceof File && value.size > 0);
      return { payload, files };
    }
    if (contentType.includes("application/json")) {
      return { payload: await request.json(), files: [] };
    }
  } catch {
    return errorResponse(400, "invalid_request", "We couldn't read that request. Please try again.");
  }
  return errorResponse(415, "invalid_request", "Send JSON, or multipart form data when attaching screenshots.");
}

/**
 * Shared request pipeline for every AI endpoint:
 * rate limit -> parse -> validate -> entitlement -> plan gate -> usage -> provider -> envelope.
 *
 * Conversation content is never logged at any step.
 */
export async function handleTask<Schema extends z.ZodType, Result>(
  request: Request,
  config: TaskConfig<Schema, Result>,
): Promise<Response> {
  const limit = checkRateLimit(clientKey(request));
  if (!limit.ok) {
    return errorResponse(429, "rate_limited", "You're going a little fast. Take a breath and try again in a moment.", {
      headers: { "Retry-After": String(limit.retryAfterSeconds) },
    });
  }

  const body = await readBody(request);
  if (body instanceof Response) return body;
  if (!body.payload || typeof body.payload !== "object") {
    return errorResponse(400, "invalid_request", "We couldn't read that request. Please try again.");
  }

  const parsed = config.schema.safeParse(body.payload);
  if (!parsed.success) {
    return errorResponse(400, "invalid_request", parsed.error.issues[0]?.message ?? "Some of the details were invalid.");
  }
  const input = parsed.data as z.infer<Schema>;

  let images: TransientImage[] = [];
  if (body.files.length > 0) {
    if (!config.allowImages) {
      return errorResponse(400, "invalid_request", "This request doesn't take screenshots.");
    }
    try {
      images = await readTransientImages(body.files);
    } catch (error) {
      if (error instanceof InputError) {
        return errorResponse(error.code === "payload_too_large" ? 413 : 400, error.code, error.message);
      }
      throw error;
    }
  }

  const invalid = config.validate?.(input, images);
  if (invalid) return errorResponse(400, "invalid_request", invalid);

  const provider = getProvider();
  const tier = resolveTier(request);
  const plan = getPlans()[tier];
  const subject = usageSubject(request);
  const context: TaskContext<z.infer<Schema>> = { input, images, tier, plan, provider };

  try {
    config.gate?.(context);
  } catch (error) {
    if (error instanceof UpgradeRequired) {
      return errorResponse(402, "upgrade_required", error.message, { usage: usageSnapshot(subject, tier) });
    }
    throw error;
  }

  let usage = usageSnapshot(subject, tier);
  if (config.meter) {
    const reserved = consumeUsage(subject, tier, config.meter);
    usage = reserved.usage;
    if (!reserved.ok) {
      const message =
        config.meter === "coach"
          ? "That's today's coaching on the free plan. It resets tomorrow, or go Pro for more."
          : tier === "free"
            ? "That's today's free replies. They reset tomorrow, or go Pro to keep going."
            : "You've reached today's limit. It resets tomorrow.";
      return errorResponse(402, "limit_reached", message, { usage });
    }
  }

  try {
    const result = await config.run(context);
    const envelope: Envelope<Result> = {
      mode: provider.mode,
      provider: provider.id,
      model: provider.modelFor(config.task),
      usage,
      result,
    };
    return Response.json(envelope, { headers: NO_STORE });
  } catch (error) {
    // The user shouldn't pay for our failures.
    if (config.meter) refundUsage(subject, tier, config.meter);
    if (error instanceof ProviderError) {
      switch (error.kind) {
        case "rate_limited":
          return errorResponse(429, "rate_limited", error.message);
        case "declined":
          return errorResponse(422, "ai_declined", error.message);
        case "bad_output":
          return errorResponse(502, "ai_bad_output", error.message);
        case "unavailable":
          return errorResponse(503, "ai_unavailable", error.message);
      }
    }
    console.error(`[replyright] Unhandled error in ${config.task}:`, error instanceof Error ? error.name : "unknown");
    return errorResponse(500, "internal", "Something went wrong on our side. Please try again.");
  }
}
