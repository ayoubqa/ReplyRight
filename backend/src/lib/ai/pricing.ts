/**
 * Anthropic list prices, in US dollars per million tokens, for estimating what
 * each call cost. Copied from https://platform.claude.com/docs/en/about-claude/pricing
 * on 13 November 2026. Check that page before relying on totals: these are
 * estimates from token counts, not Anthropic's invoice.
 *
 * Standard (global) routing and standard speed. ReplyRight does not request
 * US-only inference or fast mode, which are priced higher.
 */
export interface ModelPrice {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite5m: number;
  cacheWrite1h: number;
}

export const PRICES_CHECKED_ON = "2026-11-13";

const PRICES: Record<string, ModelPrice> = {
  "claude-fable-5-2": { input: 8, output: 40, cacheRead: 0.2, cacheWrite5m: 10, cacheWrite1h: 16 },
  "claude-fable-5-1": { input: 10, output: 50, cacheRead: 0.25, cacheWrite5m: 12.5, cacheWrite1h: 20 },
  "claude-fable-5": { input: 10, output: 50, cacheRead: 1, cacheWrite5m: 12.5, cacheWrite1h: 20 },
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2, cacheWrite5m: 5, cacheWrite1h: 8 },
  "claude-opus-5": { input: 5, output: 25, cacheRead: 0.5, cacheWrite5m: 6.25, cacheWrite1h: 10 },
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.1, cacheWrite5m: 2.5, cacheWrite1h: 4 },
  "claude-sonnet-5": { input: 2, output: 10, cacheRead: 0.2, cacheWrite5m: 2.5, cacheWrite1h: 4 },
  "claude-haiku-5-5": { input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite5m: 0.125, cacheWrite1h: 0.2 },
  "claude-haiku-4-5": { input: 1, output: 5, cacheRead: 0.1, cacheWrite5m: 1.25, cacheWrite1h: 2 },
};

/** Haiku 5.5 charges more for a request whose prompt (all input, cache included) is over 100,000 tokens. */
const LONG_PROMPT: Record<string, { threshold: number; price: ModelPrice }> = {
  "claude-haiku-5-5": {
    threshold: 100_000,
    price: { input: 0.5, output: 2.5, cacheRead: 0.05, cacheWrite5m: 0.625, cacheWrite1h: 1 },
  },
};

/**
 * Used for a model that is not in the table, so an unknown model can never
 * look free to the spend guard: the highest price of each kind in the table.
 */
const UNKNOWN: ModelPrice = { input: 10, output: 50, cacheRead: 1, cacheWrite5m: 12.5, cacheWrite1h: 20 };

/** Longest matching name first, so "claude-opus-5-5" is not priced as "claude-opus-5". */
const NAMES = Object.keys(PRICES).sort((a, b) => b.length - a.length);

function family(model: string): string | null {
  return NAMES.find((name) => model === name || model.startsWith(`${name}-`)) ?? null;
}

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheReadInputTokens: number;
  /** Cache writes, split by lifetime when the API reports it. */
  cacheWrite5mInputTokens: number;
  cacheWrite1hInputTokens: number;
}

export function estimateCostUsd(model: string, usage: TokenUsage): { costUsd: number; priced: boolean } {
  const name = family(model);
  let price = name ? PRICES[name] : UNKNOWN;
  const long = name ? LONG_PROMPT[name] : undefined;
  const prompt =
    usage.inputTokens + usage.cacheReadInputTokens + usage.cacheWrite5mInputTokens + usage.cacheWrite1hInputTokens;
  if (long && prompt > long.threshold) price = long.price;

  const cost =
    (usage.inputTokens * price.input +
      usage.outputTokens * price.output +
      usage.cacheReadInputTokens * price.cacheRead +
      usage.cacheWrite5mInputTokens * price.cacheWrite5m +
      usage.cacheWrite1hInputTokens * price.cacheWrite1h) /
    1_000_000;
  // Rounded to a millionth of a dollar, which is finer than any single token here.
  return { costUsd: Math.round(cost * 1_000_000) / 1_000_000, priced: name !== null };
}

export function knownPrice(model: string): ModelPrice | null {
  const name = family(model);
  return name ? PRICES[name] : null;
}
