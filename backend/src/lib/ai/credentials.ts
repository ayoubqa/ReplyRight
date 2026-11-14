import "server-only";
import { serverEnvironment, type ServerEnvironment } from "@/lib/server/environment";

/**
 * Which Anthropic API key this process may use.
 *
 *   ANTHROPIC_API_KEY       the production key. Used only when the server runs as production.
 *   ANTHROPIC_API_KEY_DEV   the development and testing key. Used in development and staging,
 *                           by the eval harness and by anything else that is not production.
 *
 * Development traffic never falls back to the production key. Without a
 * development key, a development server runs in the labelled demo mode and
 * says why. A development key that is identical to the production key is
 * refused too, so copying the production key into the development variable
 * does not get around the separation.
 *
 * Keys are never logged or returned to clients. Only the variable name is.
 */
export const PRODUCTION_KEY_VAR = "ANTHROPIC_API_KEY";
export const DEVELOPMENT_KEY_VAR = "ANTHROPIC_API_KEY_DEV";

export type KeySource = typeof PRODUCTION_KEY_VAR | typeof DEVELOPMENT_KEY_VAR;

export type KeyResolution =
  | { ok: true; apiKey: string; source: KeySource; environment: ServerEnvironment }
  | { ok: false; environment: ServerEnvironment; problem: "missing" | "production_key_outside_production" | "same_key"; message: string };

function read(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value ? value : undefined;
}

export function resolveAnthropicKey(environment: ServerEnvironment = serverEnvironment()): KeyResolution {
  const production = read(PRODUCTION_KEY_VAR);
  const development = read(DEVELOPMENT_KEY_VAR);

  if (environment === "production") {
    if (!production) {
      return { ok: false, environment, problem: "missing", message: `${PRODUCTION_KEY_VAR} is not set.` };
    }
    return { ok: true, apiKey: production, source: PRODUCTION_KEY_VAR, environment };
  }

  if (development && production && development === production) {
    return {
      ok: false,
      environment,
      problem: "same_key",
      message: `${DEVELOPMENT_KEY_VAR} is the same key as ${PRODUCTION_KEY_VAR}. Create a separate development key; the production key is only used in production.`,
    };
  }
  if (development) {
    return { ok: true, apiKey: development, source: DEVELOPMENT_KEY_VAR, environment };
  }
  if (production) {
    return {
      ok: false,
      environment,
      problem: "production_key_outside_production",
      message: `${PRODUCTION_KEY_VAR} is the production key and is not used in ${environment}. Put a development key in ${DEVELOPMENT_KEY_VAR}.`,
    };
  }
  return { ok: false, environment, problem: "missing", message: `${DEVELOPMENT_KEY_VAR} is not set.` };
}

/** True when an Anthropic key is configured for some environment, even if this one may not use it. */
export function anyAnthropicKeyConfigured(): boolean {
  return Boolean(read(PRODUCTION_KEY_VAR) || read(DEVELOPMENT_KEY_VAR));
}
