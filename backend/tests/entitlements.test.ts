import { beforeAll, describe, expect, it } from "vitest";
import { APPLE_ROOT_CA_G3_SHA256, verifyEntitlement, type EntitlementConfig } from "@/lib/server/entitlements";
import { createTestChain, signTransaction, xcodeTransaction, type TestChain } from "./helpers/storekit";

// Assigned after the chain exists so the certificates are already valid.
let NOW = Date.now();
const HOUR = 60 * 60 * 1000;
let chain: TestChain;
let config: EntitlementConfig;

const transaction = (overrides: Record<string, unknown> = {}) => ({
  bundleId: "com.replyright.app",
  productId: "com.replyright.pro.monthly",
  environment: "Production",
  signedDate: NOW,
  expiresDate: NOW + 24 * HOUR,
  ...overrides,
});

beforeAll(() => {
  chain = createTestChain();
  NOW = Date.now() + 2000;
  config = {
    bundleId: "com.replyright.app",
    productIds: new Set(["com.replyright.pro.monthly", "com.replyright.pro.annual"]),
    rootFingerprints: new Set([chain.rootFingerprint]),
    allowSandbox: true,
    trustXcode: false,
    requireAppleOids: false, // the throwaway chain has no Apple marker OIDs
    graceMs: HOUR,
  };
});

describe("verifyEntitlement", () => {
  it("grants Pro for a valid, unexpired transaction", () => {
    const result = verifyEntitlement(signTransaction(chain, transaction()), config, NOW);
    expect(result).toMatchObject({ tier: "pro", productId: "com.replyright.pro.monthly" });
  });

  it("rejects a chain that does not end in a trusted root", () => {
    const strict = { ...config, rootFingerprints: new Set([APPLE_ROOT_CA_G3_SHA256]) };
    expect(verifyEntitlement(signTransaction(chain, transaction()), strict, NOW)).toEqual({
      tier: "free",
      reason: "untrusted root",
    });
  });

  it("rejects a tampered payload", () => {
    const [head, , signature] = signTransaction(chain, transaction()).split(".");
    const forged = Buffer.from(JSON.stringify(transaction({ expiresDate: NOW + 9999 * HOUR }))).toString("base64url");
    expect(verifyEntitlement(`${head}.${forged}.${signature}`, config, NOW)).toEqual({
      tier: "free",
      reason: "invalid signature",
    });
  });

  it("rejects a token signed by a different key than the leaf certificate", () => {
    const other = createTestChain();
    const token = signTransaction(other, transaction(), chain.x5c);
    expect(verifyEntitlement(token, config, NOW).tier).toBe("free");
  });

  it("rejects expired, revoked, wrong-app and unknown-product transactions", () => {
    const check = (overrides: Record<string, unknown>) =>
      verifyEntitlement(signTransaction(chain, transaction(overrides)), config, NOW);
    expect(check({ expiresDate: NOW - 2 * HOUR })).toEqual({ tier: "free", reason: "expired" });
    expect(check({ revocationDate: NOW - HOUR })).toEqual({ tier: "free", reason: "revoked" });
    expect(check({ bundleId: "com.someone.else" })).toEqual({ tier: "free", reason: "wrong app" });
    expect(check({ productId: "com.replyright.tip" })).toEqual({ tier: "free", reason: "not a Pro product" });
  });

  it("keeps Pro during the short grace window after expiry", () => {
    const token = signTransaction(chain, transaction({ expiresDate: NOW - 10 * 60 * 1000 }));
    expect(verifyEntitlement(token, config, NOW).tier).toBe("pro");
  });

  it("honours the sandbox switch", () => {
    const token = signTransaction(chain, transaction({ environment: "Sandbox" }));
    expect(verifyEntitlement(token, config, NOW).tier).toBe("pro");
    expect(verifyEntitlement(token, { ...config, allowSandbox: false }, NOW).tier).toBe("free");
  });

  it("requires Apple's marker OIDs unless a test disables the check", () => {
    const token = signTransaction(chain, transaction());
    expect(verifyEntitlement(token, { ...config, requireAppleOids: true }, NOW)).toEqual({
      tier: "free",
      reason: "leaf is not an App Store signing certificate",
    });
  });

  it("only accepts Xcode local-testing tokens when explicitly trusted", () => {
    const token = xcodeTransaction(transaction());
    expect(verifyEntitlement(token, config, NOW)).toEqual({
      tier: "free",
      reason: "local test purchases are not accepted",
    });
    expect(verifyEntitlement(token, { ...config, trustXcode: true }, NOW).tier).toBe("pro");
  });

  it("treats garbage as free", () => {
    expect(verifyEntitlement("not-a-token", config, NOW).tier).toBe("free");
    expect(verifyEntitlement("a.b.c", config, NOW).tier).toBe("free");
    expect(verifyEntitlement("", config, NOW).tier).toBe("free");
  });
});
