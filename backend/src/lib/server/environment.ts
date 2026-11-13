import "server-only";

/**
 * Which deployment this is, so the app can show "development", "staging" or
 * "production" next to the address it is talking to.
 *
 *   RR_ENVIRONMENT = development | staging | production
 *
 * Without it, a production build reports "production" and `next dev` reports
 * "development".
 */
export type ServerEnvironment = "development" | "staging" | "production";

export function serverEnvironment(): ServerEnvironment {
  const value = process.env.RR_ENVIRONMENT?.trim().toLowerCase();
  if (value === "development" || value === "staging" || value === "production") return value;
  return process.env.NODE_ENV === "production" ? "production" : "development";
}
