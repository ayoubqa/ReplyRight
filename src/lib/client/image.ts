"use client";

import { LIMITS } from "@/lib/domain/replies";

const MAX_EDGE = 2000;
const MAX_INPUT_BYTES = 25 * 1024 * 1024;

export class ImageInputError extends Error {}

/**
 * Re-encodes a screenshot on-device before upload: downsizes large images and
 * strips metadata (EXIF, location) by redrawing to a canvas.
 */
export async function prepareScreenshot(file: File): Promise<Blob> {
  if (!file.type.startsWith("image/")) {
    throw new ImageInputError(`“${file.name}” isn’t an image.`);
  }
  if (file.size > MAX_INPUT_BYTES) {
    throw new ImageInputError(`“${file.name}” is too large. Try a regular screenshot.`);
  }

  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    throw new ImageInputError(`Couldn’t read “${file.name}”. Try a PNG or JPEG screenshot.`);
  }

  const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height));
  const width = Math.round(bitmap.width * scale);
  const height = Math.round(bitmap.height * scale);

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new ImageInputError("Your browser couldn’t process this image.");
  ctx.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();

  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.86));
  if (!blob) throw new ImageInputError("Your browser couldn’t process this image.");
  if (blob.size > LIMITS.maxImageBytes) {
    throw new ImageInputError(`“${file.name}” is still too large after compression.`);
  }
  return blob;
}
