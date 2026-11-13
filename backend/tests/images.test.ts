import { randomBytes } from "node:crypto";
import { deflateSync } from "node:zlib";
import sharp from "sharp";
import { describe, expect, it } from "vitest";
import {
  InputError,
  MAX_ENCODED_BYTES,
  MAX_LONG_EDGE,
  MESSAGES,
  prepareImage,
  readTransientImages,
} from "@/lib/server/images";
import { LIMITS } from "@/lib/domain/contracts";
import { asUint8, garbledJpeg, OLD_VERIFY_FIXTURE, screenshot } from "./helpers/images";

async function rejected(promise: Promise<unknown>): Promise<InputError> {
  const error = await promise.then(
    () => null,
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(InputError);
  return error as InputError;
}

/** Decodes what would be sent to the provider, to prove it is a real image of the stated type. */
async function decodeSent(image: { mediaType: string; base64: string }) {
  const bytes = Buffer.from(image.base64, "base64");
  const meta = await sharp(bytes, { failOn: "warning" }).metadata();
  await sharp(bytes, { failOn: "warning" }).raw().toBuffer();
  return { bytes, meta };
}

describe("prepareImage: valid screenshots", () => {
  it.each([
    ["png", "image/png"],
    ["jpeg", "image/jpeg"],
    ["webp", "image/webp"],
  ] as const)("sends a %s screenshot as a decodable %s image", async (format, mediaType) => {
    const image = await prepareImage(asUint8(await screenshot(format)));
    expect(image.mediaType).toBe(mediaType);
    expect([image.width, image.height]).toEqual([800, 1200]);
    const { meta } = await decodeSent(image);
    expect(`image/${meta.format}`).toBe(mediaType);
    expect([meta.width, meta.height]).toEqual([800, 1200]);
  });

  it("sends a clean JPEG from the app unchanged, so it is not compressed twice", async () => {
    const original = await screenshot("jpeg");
    const image = await prepareImage(asUint8(original));
    expect(Buffer.from(image.base64, "base64").equals(original)).toBe(true);
  });

  it("turns a GIF into a single-frame PNG", async () => {
    // The frames must differ: a GIF encoder merges identical ones.
    const frame = (background: string) =>
      sharp({ create: { width: 400, height: 600, channels: 3, background } }).png().toBuffer();
    const twoFrames = await sharp([await frame("#ece5dd"), await frame("#dcf8c6")], { join: { animated: true } })
      .gif()
      .toBuffer();
    expect((await sharp(twoFrames).metadata()).pages).toBe(2);
    const image = await prepareImage(asUint8(twoFrames));
    expect(image.mediaType).toBe("image/png");
    const { meta } = await decodeSent(image);
    expect(meta.pages ?? 1).toBe(1);
  });

  it("applies the EXIF orientation and strips metadata before anything is sent", async () => {
    const sideways = await sharp(Buffer.from((await screenshot("png", { width: 1000, height: 600 })) as Buffer))
      .jpeg()
      .withMetadata({ orientation: 6, exif: { IFD0: { Copyright: "private-marker", Artist: "someone" } } })
      .toBuffer();
    const image = await prepareImage(asUint8(sideways));
    expect([image.width, image.height]).toEqual([600, 1000]);
    const { bytes, meta } = await decodeSent(image);
    expect(meta.exif).toBeUndefined();
    expect(meta.orientation ?? 1).toBe(1);
    expect(bytes.includes(Buffer.from("private-marker"))).toBe(false);
  });

  it("scales a large screenshot down to the model's native long edge", async () => {
    const large = await screenshot("png", { width: 3000, height: 4000 });
    const image = await prepareImage(asUint8(large));
    expect(Math.max(image.width, image.height)).toBe(MAX_LONG_EDGE);
    expect(image.width / image.height).toBeCloseTo(3000 / 4000, 2);
    expect(Math.ceil(Buffer.from(image.base64, "base64").length / 3) * 4).toBeLessThanOrEqual(MAX_ENCODED_BYTES);
  });

  it("re-encodes an image that would be too large to send, and keeps it under the limit", async () => {
    // Random noise does not compress: the worst case for the encoded size.
    const noise = randomBytes(2576 * 2576 * 3);
    const photo = await sharp(noise, { raw: { width: 2576, height: 2576, channels: 3 } }).png().toBuffer();
    expect(photo.length).toBeGreaterThan(MAX_ENCODED_BYTES);
    const image = await prepareImage(asUint8(photo));
    expect(image.mediaType).toBe("image/jpeg");
    expect(Math.ceil(Buffer.from(image.base64, "base64").length / 3) * 4).toBeLessThanOrEqual(MAX_ENCODED_BYTES);
  });
});

describe("prepareImage: what is refused, and what the user is told", () => {
  it("refuses the corrupt JPEG the verification script used to send", async () => {
    const error = await rejected(prepareImage(asUint8(OLD_VERIFY_FIXTURE)));
    expect(error.code).toBe("unsupported_media");
    // It is too small to be a screenshot, and checked before its damaged data is decoded.
    expect(error.message).toBe(MESSAGES.tooSmall);
  });

  it("refuses a screenshot whose image data is garbled, even though its header looks fine", async () => {
    const broken = await garbledJpeg();
    // A lenient decode still "succeeds", which is why checking the first bytes was not enough.
    await expect(sharp(broken, { failOn: "error" }).raw().toBuffer()).resolves.toBeInstanceOf(Buffer);
    const error = await rejected(prepareImage(asUint8(broken)));
    expect(error.code).toBe("unsupported_media");
    expect(error.message).toBe(MESSAGES.damaged);
  });

  it("refuses screenshots that were only partly saved", async () => {
    for (const format of ["jpeg", "png"] as const) {
      const whole = await screenshot(format);
      const error = await rejected(prepareImage(asUint8(whole.subarray(0, Math.floor(whole.length * 0.6)))));
      expect(error.code).toBe("unsupported_media");
      expect(error.message).toBe(MESSAGES.damaged);
    }
  });

  it("refuses files that are not a supported image", async () => {
    const heic = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from("ftypheic"), Buffer.alloc(100)]);
    for (const bytes of [Buffer.from("definitely not an image"), heic, Buffer.from("%PDF-1.7\n%...")]) {
      const error = await rejected(prepareImage(asUint8(bytes)));
      expect(error.code).toBe("unsupported_media");
      expect(error.message).toBe(MESSAGES.unsupported);
    }
  });

  it("refuses images too small to read", async () => {
    for (const [width, height] of [
      [16, 16],
      [150, 150],
      [1170, 20],
    ]) {
      const tiny = await sharp({ create: { width, height, channels: 3, background: "#ffffff" } }).png().toBuffer();
      const error = await rejected(prepareImage(asUint8(tiny)));
      expect(error.message).toBe(MESSAGES.tooSmall);
    }
  });

  it("refuses an image that claims enormous dimensions without decoding it", async () => {
    // A valid PNG header for 20000x20000, followed by almost no data: a decompression bomb.
    const error = await rejected(prepareImage(asUint8(pngClaiming(20000, 20000))));
    expect(error.code).toBe("payload_too_large");
    expect(error.message).toBe(MESSAGES.tooLargeImage);
  });
});

describe("readTransientImages", () => {
  const file = (bytes: Buffer, name: string) => new File([asUint8(bytes)], name);

  it("keeps several screenshots in the order they were attached", async () => {
    const first = await screenshot("jpeg", { width: 700, height: 1200 });
    const second = await screenshot("png", { width: 900, height: 1200 });
    const images = await readTransientImages([file(first, "1.jpg"), file(second, "2.png")]);
    expect(images.map((image) => [image.mediaType, image.width])).toEqual([
      ["image/jpeg", 700],
      ["image/png", 900],
    ]);
  });

  it("refuses the whole upload when one screenshot is damaged", async () => {
    const good = await screenshot("jpeg");
    const error = await rejected(readTransientImages([file(good, "1.jpg"), file(await garbledJpeg(), "2.jpg")]));
    expect(error.message).toBe(MESSAGES.damaged);
  });

  it("enforces the count and size limits before decoding anything", async () => {
    const good = await screenshot("jpeg");
    const tooMany = Array.from({ length: LIMITS.maxImages + 1 }, (_, i) => file(good, `${i}.jpg`));
    expect((await rejected(readTransientImages(tooMany))).code).toBe("invalid_request");

    const huge = new File([new Uint8Array(LIMITS.maxImageBytes + 1)], "huge.png");
    expect((await rejected(readTransientImages([huge]))).code).toBe("payload_too_large");
  });
});

function pngClaiming(width: number, height: number): Buffer {
  const table = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (bytes: Buffer) => {
    let c = 0xffffffff;
    for (const byte of bytes) c = table[(c ^ byte) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type: string, data: Buffer) => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type), data]);
    const sum = Buffer.alloc(4);
    sum.writeUInt32BE(crc(body));
    return Buffer.concat([length, body, sum]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; // bit depth
  header[9] = 0; // greyscale
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(Buffer.alloc(width + 1))),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}
