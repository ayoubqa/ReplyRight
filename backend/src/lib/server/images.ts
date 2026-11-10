import "server-only";
import { ACCEPTED_IMAGE_TYPES, LIMITS, type AcceptedImageType } from "@/lib/domain/contracts";
import type { TransientImage } from "@/lib/ai/types";

export class InputError extends Error {
  constructor(
    public readonly code: "invalid_request" | "unsupported_media" | "payload_too_large",
    message: string,
  ) {
    super(message);
  }
}

/** Detect the real image type from magic bytes rather than trusting the client. */
function sniffImageType(bytes: Uint8Array): AcceptedImageType | null {
  if (bytes.length < 12) return null;
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "image/png";
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) return "image/gif";
  if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) return "image/webp";
  return null;
}

/**
 * Reads uploaded screenshots into memory for a single request.
 * Nothing is written to disk, logged, or retained after the response is sent.
 */
export async function readTransientImages(files: File[]): Promise<TransientImage[]> {
  if (files.length > LIMITS.maxImages) {
    throw new InputError("invalid_request", `You can add up to ${LIMITS.maxImages} screenshots at a time.`);
  }

  return Promise.all(
    files.map(async (file) => {
      if (file.size > LIMITS.maxImageBytes) {
        throw new InputError("payload_too_large", "One of the screenshots is too large. Try a smaller image.");
      }
      const bytes = new Uint8Array(await file.arrayBuffer());
      const mediaType = sniffImageType(bytes);
      if (!mediaType || !(ACCEPTED_IMAGE_TYPES as readonly string[]).includes(mediaType)) {
        throw new InputError("unsupported_media", "Screenshots must be PNG, JPEG, WebP or GIF images.");
      }
      return { mediaType, base64: Buffer.from(bytes).toString("base64") };
    }),
  );
}
