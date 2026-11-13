import { execFileSync } from "node:child_process";
import { createPrivateKey, sign, X509Certificate, type KeyObject } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * Builds a throwaway root -> intermediate -> leaf certificate chain with
 * OpenSSL and signs StoreKit-shaped JWS tokens with it, so entitlement
 * verification can be tested without Apple's private keys.
 */
export interface TestChain {
  x5c: string[];
  leafKey: KeyObject;
  rootFingerprint: string;
}

function openssl(args: string[], cwd: string) {
  execFileSync("openssl", args, { cwd, stdio: "pipe" });
}

export function createTestChain(): TestChain {
  const dir = mkdtempSync(join(tmpdir(), "rr-chain-"));
  writeFileSync(join(dir, "ca.ext"), "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n");
  writeFileSync(join(dir, "leaf.ext"), "basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\n");

  for (const name of ["root", "inter", "leaf"]) {
    openssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `${name}.key`], dir);
  }
  openssl(["req", "-x509", "-new", "-key", "root.key", "-subj", "/CN=Test Root", "-days", "2", "-out", "root.pem",
    "-addext", "basicConstraints=critical,CA:TRUE"], dir);
  openssl(["req", "-new", "-key", "inter.key", "-subj", "/CN=Test Intermediate", "-out", "inter.csr"], dir);
  openssl(["x509", "-req", "-in", "inter.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial",
    "-days", "2", "-extfile", "ca.ext", "-out", "inter.pem"], dir);
  openssl(["req", "-new", "-key", "leaf.key", "-subj", "/CN=Test Leaf", "-out", "leaf.csr"], dir);
  openssl(["x509", "-req", "-in", "leaf.csr", "-CA", "inter.pem", "-CAkey", "inter.key", "-CAcreateserial",
    "-days", "2", "-extfile", "leaf.ext", "-out", "leaf.pem"], dir);

  const certs = ["leaf", "inter", "root"].map((name) => new X509Certificate(readFileSync(join(dir, `${name}.pem`))));
  return {
    x5c: certs.map((cert) => cert.raw.toString("base64")),
    leafKey: createPrivateKey(readFileSync(join(dir, "leaf.key"))),
    rootFingerprint: certs[2].fingerprint256,
  };
}

const b64url = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");

export function signTransaction(chain: TestChain, payload: Record<string, unknown>, x5c = chain.x5c): string {
  const head = b64url({ alg: "ES256", x5c });
  const body = b64url(payload);
  const signature = sign("sha256", Buffer.from(`${head}.${body}`), { key: chain.leafKey, dsaEncoding: "ieee-p1363" });
  return `${head}.${body}.${signature.toString("base64url")}`;
}

/** A token shaped like Xcode's local StoreKit testing output: not signed by Apple. */
export function xcodeTransaction(payload: Record<string, unknown>): string {
  return `${b64url({ alg: "ES256", x5c: [] })}.${b64url({ ...payload, environment: "Xcode" })}.${Buffer.from("local").toString("base64url")}`;
}
