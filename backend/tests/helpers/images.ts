import sharp from "sharp";

/**
 * Test images, generated in memory. They look like a chat (bubbles on a
 * background) so their dimensions and compression are realistic, but they
 * contain no text and nothing personal.
 */
export function chatSvg(width = 800, height = 1200, bubbles = 10): Buffer {
  const rows = Array.from({ length: bubbles }, (_, i) => {
    const mine = i % 2 === 1;
    const y = 40 + i * Math.floor((height - 80) / bubbles);
    return `<rect x="${mine ? width * 0.35 : 20}" y="${y}" width="${width * 0.6}" height="${Math.floor((height - 80) / bubbles) - 24}" rx="18" fill="${mine ? "#dcf8c6" : "#ffffff"}"/>`;
  }).join("");
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="#ece5dd"/>${rows}</svg>`,
  );
}

export async function screenshot(
  format: "png" | "jpeg" | "webp" | "gif",
  { width = 800, height = 1200 }: { width?: number; height?: number } = {},
): Promise<Buffer> {
  const image = sharp(chatSvg(width, height));
  switch (format) {
    case "png":
      return image.png().toBuffer();
    case "jpeg":
      return image.jpeg({ quality: 85 }).toBuffer();
    case "webp":
      return image.webp().toBuffer();
    case "gif":
      return image.gif().toBuffer();
  }
}

/** A JPEG whose entropy-coded data is garbled in the middle, while its header and end marker are intact. */
export async function garbledJpeg(): Promise<Buffer> {
  const jpeg = await screenshot("jpeg");
  const broken = Buffer.from(jpeg);
  const start = Math.floor(jpeg.length * 0.4);
  for (let i = start; i < start + 400; i++) broken[i] = (i * 37) & 0xff;
  return broken;
}

/**
 * The 16x16 JPEG that `scripts/verify.mjs` used to upload. Its header is valid
 * but its scan data is not (libjpeg: "Corrupt JPEG data: premature end of data
 * segment"). Lenient decoders open it anyway; the AI provider did not.
 */
export const OLD_VERIFY_FIXTURE = Buffer.from(
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAAQABABAREA/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAA/AKpgA//Z",
  "base64",
);

export function asUint8(buffer: Buffer): Uint8Array<ArrayBuffer> {
  const copy = new Uint8Array(new ArrayBuffer(buffer.byteLength));
  copy.set(buffer);
  return copy;
}
