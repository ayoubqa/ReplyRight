import { getReplyProvider, ProviderError } from "@/lib/ai";
import {
  replyRequestSchema,
  type ApiErrorBody,
  type ApiErrorCode,
  type ReplyResponse,
} from "@/lib/domain/replies";
import { InputError, readTransientImages } from "@/lib/server/images";
import { checkRateLimit, clientKey } from "@/lib/server/rate-limit";

export const maxDuration = 60;

function errorResponse(status: number, code: ApiErrorCode, message: string, headers?: HeadersInit) {
  const body: ApiErrorBody = { error: { code, message } };
  return Response.json(body, { status, headers: { "Cache-Control": "no-store", ...headers } });
}

export async function POST(request: Request) {
  const limit = checkRateLimit(clientKey(request));
  if (!limit.ok) {
    return errorResponse(429, "rate_limited", "You're going a little fast. Take a breath and try again in a moment.", {
      "Retry-After": String(limit.retryAfterSeconds),
    });
  }

  if (!request.headers.get("content-type")?.includes("multipart/form-data")) {
    return errorResponse(415, "invalid_request", "Expected a multipart form submission.");
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return errorResponse(400, "invalid_request", "We couldn't read that submission. Please try again.");
  }

  const rawPayload = form.get("payload");
  let payloadJson: unknown;
  try {
    payloadJson = typeof rawPayload === "string" ? JSON.parse(rawPayload) : null;
  } catch {
    payloadJson = null;
  }
  if (!payloadJson || typeof payloadJson !== "object") {
    return errorResponse(400, "invalid_request", "We couldn't read that request. Please try again.");
  }
  const parsed = replyRequestSchema.safeParse(payloadJson);
  if (!parsed.success) {
    const message = parsed.error.issues[0]?.message ?? "Some of the details were invalid.";
    return errorResponse(400, "invalid_request", message);
  }
  const replyRequest = parsed.data;

  const files = form.getAll("images").filter((value): value is File => value instanceof File && value.size > 0);
  const provider = getReplyProvider();

  let images;
  try {
    images = await readTransientImages(files);
  } catch (error) {
    if (error instanceof InputError) {
      return errorResponse(error.code === "payload_too_large" ? 413 : 400, error.code, error.message);
    }
    throw error;
  }

  if (!replyRequest.conversation && images.length === 0) {
    return errorResponse(400, "invalid_request", "Add a screenshot or paste a few messages so there's something to reply to.");
  }
  if (replyRequest.conversation && replyRequest.conversation.length < 2) {
    return errorResponse(400, "invalid_request", "Paste a little more of the conversation.");
  }

  try {
    const result = await provider.generateReplies({ request: replyRequest, images });
    const body: ReplyResponse = {
      mode: provider.mode,
      provider: provider.id,
      model: provider.model,
      result,
    };
    return Response.json(body, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
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
    console.error("[replyright] Unhandled error generating replies:", error);
    return errorResponse(500, "internal", "Something went wrong on our side. Please try again.");
  }
}
