"use client";

import type { ApiErrorBody, ApiErrorCode, ReplyRequest, ReplyResponse } from "@/lib/domain/replies";

export class ApiClientError extends Error {
  constructor(
    message: string,
    public readonly code: ApiErrorCode | "network",
  ) {
    super(message);
  }
}

export async function requestReplies(
  payload: ReplyRequest,
  images: Blob[],
  signal?: AbortSignal,
): Promise<ReplyResponse> {
  const form = new FormData();
  form.set("payload", JSON.stringify(payload));
  images.forEach((image, i) => form.append("images", image, `screenshot-${i + 1}.jpg`));

  let res: Response;
  try {
    res = await fetch("/api/replies", { method: "POST", body: form, signal });
  } catch (error) {
    if ((error as Error).name === "AbortError") throw error;
    throw new ApiClientError("You seem to be offline. Check your connection and try again.", "network");
  }

  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as ApiErrorBody | null;
    throw new ApiClientError(
      body?.error?.message ?? "Something went wrong. Please try again.",
      body?.error?.code ?? "internal",
    );
  }
  return (await res.json()) as ReplyResponse;
}
