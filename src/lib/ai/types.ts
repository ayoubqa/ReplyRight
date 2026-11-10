import "server-only";
import type { AcceptedImageType, GenerationMode, ReplyRequest, ReplyResult } from "@/lib/domain/replies";

/** A screenshot held in memory for the duration of a single request. Never persisted. */
export interface TransientImage {
  mediaType: AcceptedImageType;
  base64: string;
}

export interface GenerateRepliesInput {
  request: ReplyRequest;
  images: TransientImage[];
}

/**
 * Provider abstraction for a multimodal LLM. Add a new provider by implementing
 * this interface and registering it in `./index.ts`.
 */
export interface ReplyProvider {
  readonly id: string;
  readonly mode: GenerationMode;
  readonly model: string | null;
  readonly supportsImages: boolean;
  generateReplies(input: GenerateRepliesInput): Promise<ReplyResult>;
}

export class ProviderError extends Error {
  constructor(
    public readonly kind: "unavailable" | "declined" | "bad_output" | "rate_limited",
    message: string,
    options?: { cause?: unknown },
  ) {
    super(message, options);
    this.name = "ProviderError";
  }
}
