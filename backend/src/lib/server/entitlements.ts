import "server-only";
import { createHash, verify as verifySignature, X509Certificate } from "node:crypto";
import type { Tier } from "@/lib/domain/contracts";

/**
 * Subscription verification.
 *
 * The app never tells the server "I am Pro". It forwards the StoreKit 2 signed
 * transaction (a JWS) for its current subscription in the `X-RR-Entitlement`
 * header, and the server verifies it independently:
 *
 *   1. the x5c certificate chain ends in Apple Root CA - G3 (pinned by SHA-256)
 *   2. each certificate is signed by the next and carries Apple's App Store OIDs
 *   3. the ES256 signature over the payload is valid for the leaf certificate
 *   4. the payload is for this app's bundle id and a known Pro product,
 *      has not expired and has not been revoked
 *
 * Anything that fails verification is treated as the free tier.
 */
export const APPLE_ROOT_CA_G3_SHA256 =
  "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";

/** DER encodings of Apple's marker OIDs. */
const OID_APP_STORE_LEAF = Buffer.from("060a2a864886f76364060b01", "hex"); // 1.2.840.113635.100.6.11.1
const OID_WWDR_INTERMEDIATE = Buffer.from("060a2a864886f76364060201", "hex"); // 1.2.840.113635.100.6.2.1

export const DEFAULT_PRO_PRODUCT_IDS = ["com.replyright.pro.monthly", "com.replyright.pro.annual"];

export interface EntitlementConfig {
  /** Expected bundle id. When null the check is skipped (development only). */
  bundleId: string | null;
  productIds: Set<string>;
  rootFingerprints: Set<string>;
  /** Accept Sandbox transactions (TestFlight and App Review use the sandbox). */
  allowSandbox: boolean;
  /** Accept unsigned-by-Apple transactions from Xcode's local StoreKit testing. Development only. */
  trustXcode: boolean;
  /** Apple marker OID checks. Disabled only by tests that use a locally generated chain. */
  requireAppleOids: boolean;
  /** Tolerance after expiry, to ride out renewal timing. */
  graceMs: number;
}

export type EntitlementResult =
  | { tier: "pro"; productId: string; expiresAt: number | null; environment: string }
  | { tier: "free"; reason: string };

interface TransactionPayload {
  bundleId?: string;
  productId?: string;
  expiresDate?: number;
  revocationDate?: number;
  environment?: string;
  signedDate?: number;
}

export function entitlementConfigFromEnv(): EntitlementConfig {
  const list = (name: string) =>
    (process.env[name] ?? "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  const productIds = list("PRO_PRODUCT_IDS");
  const trustXcode = process.env.ENTITLEMENT_TRUST_XCODE?.trim().toLowerCase() === "true";
  if (trustXcode && process.env.NODE_ENV === "production") {
    console.warn("[replyright] ENTITLEMENT_TRUST_XCODE is on in production. Local StoreKit test purchases will unlock Pro.");
  }
  return {
    bundleId: process.env.APPLE_BUNDLE_ID?.trim() || null,
    productIds: new Set(productIds.length ? productIds : DEFAULT_PRO_PRODUCT_IDS),
    rootFingerprints: new Set([APPLE_ROOT_CA_G3_SHA256]),
    allowSandbox: process.env.ENTITLEMENT_ALLOW_SANDBOX?.trim().toLowerCase() !== "false",
    trustXcode,
    requireAppleOids: true,
    graceMs: 60 * 60 * 1000,
  };
}

function decodeSegment<T>(segment: string): T {
  return JSON.parse(Buffer.from(segment, "base64url").toString("utf8")) as T;
}

function free(reason: string): EntitlementResult {
  return { tier: "free", reason };
}

function chainIsTrusted(x5c: string[], config: EntitlementConfig, at: number): string | null {
  if (x5c.length < 2) return "certificate chain too short";
  let certs: X509Certificate[];
  try {
    certs = x5c.map((der) => new X509Certificate(Buffer.from(der, "base64")));
  } catch {
    return "unreadable certificate";
  }
  const root = certs[certs.length - 1];
  if (!config.rootFingerprints.has(root.fingerprint256)) return "untrusted root";

  for (let i = 0; i < certs.length; i++) {
    const cert = certs[i];
    if (at < Date.parse(cert.validFrom) || at > Date.parse(cert.validTo)) return "certificate outside validity period";
    const issuer = certs[i + 1] ?? root; // the root is self-signed
    if (!cert.verify(issuer.publicKey)) return "broken certificate chain";
  }
  if (config.requireAppleOids) {
    if (!certs[0].raw.includes(OID_APP_STORE_LEAF)) return "leaf is not an App Store signing certificate";
    if (certs.length > 2 && !certs[1].raw.includes(OID_WWDR_INTERMEDIATE)) return "intermediate is not Apple WWDR";
  }
  return null;
}

/** Verifies a StoreKit 2 signed transaction and decides the tier it grants. */
export function verifyEntitlement(jws: string, config: EntitlementConfig, now = Date.now()): EntitlementResult {
  const parts = jws.split(".");
  if (parts.length !== 3 || jws.length > 16_000) return free("malformed token");

  let header: { alg?: string; x5c?: string[] };
  let payload: TransactionPayload;
  try {
    header = decodeSegment(parts[0]);
    payload = decodeSegment(parts[1]);
  } catch {
    return free("malformed token");
  }

  const environment = payload.environment ?? "Production";
  const locallySigned = environment === "Xcode";

  if (locallySigned) {
    if (!config.trustXcode) return free("local test purchases are not accepted");
  } else {
    if (header.alg !== "ES256" || !Array.isArray(header.x5c)) return free("unsupported token");
    const problem = chainIsTrusted(header.x5c, config, payload.signedDate ?? now);
    if (problem) return free(problem);
    const leaf = new X509Certificate(Buffer.from(header.x5c[0], "base64"));
    const valid = verifySignature(
      "sha256",
      Buffer.from(`${parts[0]}.${parts[1]}`),
      { key: leaf.publicKey, dsaEncoding: "ieee-p1363" },
      Buffer.from(parts[2], "base64url"),
    );
    if (!valid) return free("invalid signature");
    if (environment === "Sandbox" && !config.allowSandbox) return free("sandbox purchases are not accepted");
  }

  if (config.bundleId && payload.bundleId !== config.bundleId) return free("wrong app");
  if (!payload.productId || !config.productIds.has(payload.productId)) return free("not a Pro product");
  if (payload.revocationDate) return free("revoked");
  if (typeof payload.expiresDate === "number" && payload.expiresDate + config.graceMs < now) return free("expired");

  return { tier: "pro", productId: payload.productId, expiresAt: payload.expiresDate ?? null, environment };
}

// Verification involves several signature checks, so results are cached briefly by token hash.
const cache = new Map<string, { result: EntitlementResult; at: number }>();
const CACHE_TTL_MS = 5 * 60 * 1000;

export function resolveTier(request: Request, config = entitlementConfigFromEnv(), now = Date.now()): Tier {
  const token = request.headers.get("x-rr-entitlement")?.trim();
  if (!token) return "free";

  const key = createHash("sha256").update(token).digest("hex");
  const hit = cache.get(key);
  let result = hit && now - hit.at < CACHE_TTL_MS ? hit.result : null;
  if (!result) {
    result = verifyEntitlement(token, config, now);
    if (cache.size > 5000) cache.clear();
    cache.set(key, { result, at: now });
  }
  // Expiry is re-checked on every request, even for cached verifications.
  if (result.tier === "pro" && result.expiresAt !== null && result.expiresAt + config.graceMs < now) return "free";
  return result.tier;
}

/** For tests. */
export function resetEntitlementCache() {
  cache.clear();
}
