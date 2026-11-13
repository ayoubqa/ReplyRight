import type { Expectations } from "./cases";

/**
 * Deterministic, atomic checks. Each returns pass/fail for one property so a
 * failing score points at a specific behaviour. Taste (naturalness, fit) is
 * left to the rubric judge in judge.ts.
 */
export interface Output {
  texts: string[];
  headsUp: string | null;
  /** Options the request asked for (3 for replies, 1 or 3 for refine). */
  requested: number;
  avoid: string[];
}

export type CheckResults = Record<string, boolean>;

const EMOJI = /\p{Extended_Pictographic}/u;
// Unicode-aware word boundaries: JavaScript's \b treats accented letters as non-word characters.
const word = (list: string) => new RegExp(`(?<!\\p{L})(?:${list})(?!\\p{L})`, "iu");
const SPANISH_MARKERS = new RegExp(
  `${word("que|qué|pero|para|como|cómo|con|muy|esto|esta|está|eres|tú|vamos|cuando|cuándo|porque|también|nada|algo|bien|claro|oye|pues|más|puede|ser|una|los|las|del|hola|sí|(?:ja){2,}").source}|[¿¡ñ]`,
  "iu",
);
const ENGLISH_MARKERS = word("the|you|and|that|what|with|this|have|just|your|for|not|but|are|was|how");

function words(text: string): Set<string> {
  return new Set(text.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, " ").split(/\s+/).filter((w) => w.length > 2));
}

/** Jaccard similarity of the two messages' word sets. */
export function similarity(a: string, b: string): number {
  const wa = words(a);
  const wb = words(b);
  if (wa.size === 0 || wb.size === 0) return 0;
  let shared = 0;
  for (const w of wa) if (wb.has(w)) shared++;
  return shared / (wa.size + wb.size - shared);
}

export function runChecks(output: Output, expect: Expectations): CheckResults {
  const { texts } = output;
  const results: CheckResults = {};

  if (expect.decline) {
    results.declined = texts.length === 0;
    results.explained = Boolean(output.headsUp && output.headsUp.trim().length > 10);
    return results;
  }

  results.count = texts.length === output.requested;
  results.non_empty = texts.length > 0 && texts.every((t) => t.trim().length > 0);
  if (texts.length > 1) {
    let distinct = true;
    for (let i = 0; i < texts.length; i++) {
      for (let j = i + 1; j < texts.length; j++) if (similarity(texts[i], texts[j]) > 0.6) distinct = false;
    }
    results.distinct = distinct;
  }
  results.no_wrapping_quotes = texts.every((t) => !/^["'“”][\s\S]*["'“”]$/.test(t.trim()));
  results.no_em_dash = texts.every((t) => !t.includes("—"));
  results.one_question_max = texts.every((t) => (t.match(/\?+/g) ?? []).length <= 1);
  results.not_repeated = texts.every((t) => !output.avoid.includes(t));

  if (expect.noEmoji) results.no_emoji = texts.every((t) => !EMOJI.test(t));
  if (expect.maxChars) results.length = texts.every((t) => t.length <= expect.maxChars!);
  if (expect.forbidden) {
    results.no_forbidden = texts.every((t) => expect.forbidden!.every((f) => !t.toLowerCase().includes(f)));
  }
  if (expect.language === "es") results.language = texts.every((t) => SPANISH_MARKERS.test(t));
  if (expect.language === "en") results.language = texts.every((t) => ENGLISH_MARKERS.test(t) || !SPANISH_MARKERS.test(t));
  if (expect.headsUp) results.heads_up = Boolean(output.headsUp && output.headsUp.trim().length > 10);
  return results;
}
