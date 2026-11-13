import "server-only";
import sharp, { type Metadata, type OutputInfo, type Sharp } from "sharp";
import type { TransientImage } from "@/lib/ai/types";
import { ACCEPTED_IMAGE_TYPES, LIMITS, type AcceptedImageType } from "@/lib/domain/contracts";

/**
 * Screenshots: from the upload to the image blocks Claude reads.
 *
 * Every screenshot is fully decoded on the server before anything is sent to
 * the AI provider. A file that only looks like an image (right first bytes,
 * damaged data) is refused here with a message the user can act on, instead of
 * failing later inside the provider.
 *
 * Images are handled as in-memory buffers for one request. Nothing is written
 * to disk, cached or logged, and sharp's own operation cache is switched off.
 */
sharp.cache(false);

export class InputError extends Error {
  constructor(
    public readonly code: "invalid_request" | "unsupported_media" | "payload_too_large",
    message: string,
  ) {
    super(message);
    this.name = "InputError";
  }
}

/** Claude's largest native long edge for the models ReplyRight uses. Larger images are scaled down here. */
export const MAX_LONG_EDGE = 2576;
/** Below this the text in a screenshot cannot be read reliably (the API docs warn under 200 px). */
export const MIN_LONG_EDGE = 200;
export const MIN_SHORT_EDGE = 32;
/** The API's own per-image dimension limit, also a guard against decompression bombs. */
export const MAX_INPUT_PIXELS = 8000 * 8000;
/**
 * Upper bound for one image as sent to the provider, base64-encoded. The Claude
 * API allows 10 MB; 5 MB also fits Amazon Bedrock and Google Cloud.
 */
export const MAX_ENCODED_BYTES = 5 * 1024 * 1024;

export const MESSAGES = {
  tooMany: `You can add up to ${LIMITS.maxImages} screenshots at a time.`,
  tooLargeFile: "One of the screenshots is too large. Try a smaller image.",
  tooLargeImage: "One of the screenshots is too large to read. Try a regular screenshot.",
  unsupported:
    "Screenshots need to be PNG, JPEG, WebP or GIF images. On iPhone, sharing a screenshot from Photos or the screenshot preview works.",
  damaged:
    "One of the screenshots couldn't be opened. It may be damaged or only partly saved. Take it again, or paste the text instead.",
  tooSmall: "One of the screenshots is too small to read. Share the full screenshot, not a thumbnail.",
} as const;

/** Detects the real image type from its first bytes rather than trusting the client. */
export function sniffImageType(bytes: Uint8Array): AcceptedImageType | null {
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
 * Warnings from the decoder that mean pixels are missing or wrong, as opposed
 * to harmless quirks such as a few stray bytes before a marker.
 */
const DAMAGE =
  /premature end|truncat|huffman|unexpected end|not enough|read error|bad (?:data|block|length|seek)|invalid|crc|corrupt header|corrupt(?! JPEG data: \d+ extraneous)/i;

const OPEN = { limitInputPixels: MAX_INPUT_PIXELS, pages: 1, failOn: "warning" } as const;

/**
 * Decodes one screenshot completely and returns it as Claude should see it:
 * upright, no larger than the model reads, without metadata, in a format the
 * API accepts. Throws InputError with a user-facing message when it cannot.
 */
export async function prepareImage(bytes: Uint8Array): Promise<TransientImage> {
  const sniffed = sniffImageType(bytes);
  if (!sniffed || !(ACCEPTED_IMAGE_TYPES as readonly string[]).includes(sniffed)) {
    throw new InputError("unsupported_media", MESSAGES.unsupported);
  }
  const input = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);

  let info: Metadata;
  try {
    info = await sharp(input, OPEN).metadata();
  } catch (error) {
    throw decodeFailure(error);
  }
  if (!info.width || !info.height) {
    throw new InputError("unsupported_media", MESSAGES.damaged);
  }
  if (info.width * info.height > MAX_INPUT_PIXELS) {
    throw new InputError("payload_too_large", MESSAGES.tooLargeImage);
  }

  // EXIF orientations 5 to 8 swap width and height once applied.
  const swaps = (info.orientation ?? 1) >= 5;
  const width = swaps ? info.height : info.width;
  const height = swaps ? info.width : info.height;
  const longEdge = Math.max(width, height);
  const shortEdge = Math.min(width, height);
  if (longEdge < MIN_LONG_EDGE || shortEdge < MIN_SHORT_EDGE) {
    throw new InputError("unsupported_media", MESSAGES.tooSmall);
  }

  // Decode every pixel. A damaged file is caught here, before it reaches the provider.
  let strict = true;
  try {
    await sharp(input, OPEN).raw().toBuffer();
  } catch (error) {
    if (isDamage(error)) throw new InputError("unsupported_media", MESSAGES.damaged);
    // A harmless decoder warning. The image is re-encoded from a tolerant decode below.
    strict = false;
  }

  // The original bytes are sent unchanged when nothing needs fixing, so a JPEG
  // from the app is not compressed a second time.
  const needsWork =
    !strict ||
    sniffed === "image/gif" ||
    longEdge > MAX_LONG_EDGE ||
    (info.orientation ?? 1) !== 1 ||
    Boolean(info.exif) ||
    Boolean(info.xmp) ||
    Boolean(info.iptc);
  if (!needsWork && base64Length(input.byteLength) <= MAX_ENCODED_BYTES) {
    return { mediaType: sniffed, base64: input.toString("base64"), width, height };
  }

  return reencode(input, sniffed, strict);
}

/**
 * Upright, resized, metadata removed. PNG sources stay lossless when they fit;
 * otherwise high-quality JPEG, then smaller sizes, until the image fits the
 * per-image limit. Text stays legible at every step: the smallest step is the
 * standard vision resolution.
 */
async function reencode(input: Buffer, source: AcceptedImageType, strict: boolean): Promise<TransientImage> {
  const base = (edge: number) =>
    sharp(input, { ...OPEN, failOn: strict ? "warning" : "error" })
      .rotate()
      .resize({ width: edge, height: edge, fit: "inside", withoutEnlargement: true });

  type Attempt = { mediaType: AcceptedImageType; edge: number; encode: (image: Sharp) => Sharp };
  const jpeg = (edge: number, quality: number, chroma: "4:4:4" | "4:2:0"): Attempt => ({
    mediaType: "image/jpeg",
    edge,
    // Full chroma keeps coloured text and message bubbles crisp; 4:2:0 only as a last resort.
    encode: (image) => image.flatten({ background: "#ffffff" }).jpeg({ quality, chromaSubsampling: chroma }),
  });
  const attempts: Attempt[] = [];
  if (source === "image/png" || source === "image/gif") {
    attempts.push({ mediaType: "image/png", edge: MAX_LONG_EDGE, encode: (image) => image.png({ compressionLevel: 9 }) });
  }
  attempts.push(
    jpeg(MAX_LONG_EDGE, 92, "4:4:4"),
    jpeg(MAX_LONG_EDGE, 85, "4:4:4"),
    jpeg(2048, 82, "4:2:0"),
    jpeg(1568, 80, "4:2:0"),
  );

  for (const attempt of attempts) {
    let output: { data: Buffer; info: OutputInfo };
    try {
      output = await attempt.encode(base(attempt.edge)).toBuffer({ resolveWithObject: true });
    } catch (error) {
      throw decodeFailure(error);
    }
    if (base64Length(output.data.byteLength) <= MAX_ENCODED_BYTES) {
      return {
        mediaType: attempt.mediaType,
        base64: output.data.toString("base64"),
        width: output.info.width,
        height: output.info.height,
      };
    }
  }
  throw new InputError("payload_too_large", MESSAGES.tooLargeImage);
}

/**
 * Reads uploaded screenshots into memory for a single request, in the order
 * they were attached. Nothing is written to disk, logged, or retained after
 * the response is sent.
 */
export async function readTransientImages(files: File[]): Promise<TransientImage[]> {
  if (files.length > LIMITS.maxImages) {
    throw new InputError("invalid_request", MESSAGES.tooMany);
  }
  for (const file of files) {
    if (file.size > LIMITS.maxImageBytes) {
      throw new InputError("payload_too_large", MESSAGES.tooLargeFile);
    }
  }
  // One at a time keeps peak memory to a single decoded screenshot.
  const prepared: TransientImage[] = [];
  for (const file of files) {
    prepared.push(await prepareImage(new Uint8Array(await file.arrayBuffer())));
  }
  return prepared;
}

function base64Length(bytes: number): number {
  return Math.ceil(bytes / 3) * 4;
}

function isDamage(error: unknown): boolean {
  return error instanceof Error && DAMAGE.test(error.message);
}

function decodeFailure(error: unknown): InputError {
  if (error instanceof Error && /pixel limit/i.test(error.message)) {
    return new InputError("payload_too_large", MESSAGES.tooLargeImage);
  }
  if (error instanceof Error && /unsupported image format/i.test(error.message)) {
    return new InputError("unsupported_media", MESSAGES.unsupported);
  }
  return new InputError("unsupported_media", MESSAGES.damaged);
}
