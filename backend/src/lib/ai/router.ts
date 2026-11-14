import "server-only";
import type { CoachRequest, RefineRequest, RepliesRequest } from "@/lib/domain/contracts";
import type { BetaThinkingConfigParam } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import { knownPrice } from "./pricing";
import type { AiTask, TransientImage } from "./types";

/**
 * ModelRouter: which model, effort and thinking setting each kind of request
 * uses. This is the one place model assignments live; endpoints only say what
 * they were asked to do.
 *
 * Routes
 * ------
 *   read_text          analyze, pasted conversation
 *   read_screenshot    analyze, with screenshots
 *   reply_simple       replies to a short, light, text-only conversation (see isSimpleReply)
 *   reply_standard     every other text reply, and "three more"
 *   reply_screenshot   replies written straight from screenshots
 *   starter            conversation starters
 *   refine             tweaks to one message (shorter, funnier, more like me...)
 *   tone               tone rewrites (flirty, playful, charming, low-key, warm)
 *   coach_ask          a question to the coach
 *   coach_review       feedback on a message the user wrote
 *   coach_practice     a rehearsal turn
 *   coach_advanced     coaching with depth "deep" (Pro only; the app does not ask for it yet)
 *
 * Configuration, highest precedence first
 * ---------------------------------------
 *   AI_ROUTING=off                 every route uses the pre-routing setup: AI_MODEL_<TASK>,
 *                                  AI_MODEL or claude-opus-5-5, adaptive thinking. The rollback switch.
 *   AI_ROUTE_<ROUTE>               "model[,effort=low|medium|high][,thinking=auto|off][,fallback=model|none]"
 *                                  for one route, e.g. AI_ROUTE_REPLY_SIMPLE="claude-sonnet-5-5,thinking=off".
 *   AI_MODEL_<TASK>, AI_MODEL      as before: a model for every route of that task, or for all.
 *   AI_EFFORT_<TASK>, AI_EFFORT    as before: effort for every route of that task, or for all.
 *   built-in defaults              DEFAULT_ROUTES below.
 *
 * The defaults are a starting hypothesis to be confirmed by `npm run eval`.
 * Thinking stays adaptive on every route by default, as it is today, so the
 * first change is the model only. "thinking=off" is an option the eval tests.
 */
export const ROUTES = [
  "read_text",
  "read_screenshot",
  "reply_simple",
  "reply_standard",
  "reply_screenshot",
  "starter",
  "refine",
  "tone",
  "coach_ask",
  "coach_review",
  "coach_practice",
  "coach_advanced",
] as const;
export type RouteKey = (typeof ROUTES)[number];

export type Effort = "low" | "medium" | "high";
/** auto: the model's own adaptive thinking. off: the lowest setting the model accepts. */
export type ThinkingMode = "auto" | "off";

export interface RoutePolicy {
  model: string;
  effort: Effort;
  thinking: ThinkingMode;
  /**
   * Tried once if this model refuses and it has no server-side refusal
   * fallback of its own (Haiku). Never used for errors, timeouts or unusable
   * output, so a failure is not quietly re-sent to a bigger model.
   */
  fallback: string | null;
  /** Where the model came from, for the start-up log and /status. */
  source: string;
}

export type RouteTable = Record<RouteKey, RoutePolicy>;

export const HAIKU = "claude-haiku-5-5";
export const SONNET = "claude-sonnet-5-5";
export const OPUS = "claude-opus-5-5";
/** The model every task used before routing. Still the rollback target. */
export const LEGACY_MODEL = OPUS;

export const TASK_OF: Record<RouteKey, AiTask> = {
  read_text: "analyze",
  read_screenshot: "analyze",
  reply_simple: "replies",
  reply_standard: "replies",
  reply_screenshot: "replies",
  starter: "replies",
  refine: "refine",
  tone: "refine",
  coach_ask: "coach",
  coach_review: "coach",
  coach_practice: "coach",
  coach_advanced: "coach",
};

/** The route whose model /status reports for each task (and the app shows). */
export const PRIMARY_ROUTE: Record<AiTask, RouteKey> = {
  analyze: "read_screenshot",
  replies: "reply_standard",
  refine: "refine",
  coach: "coach_ask",
};

/** Effort per task, unchanged from before routing. */
export const TASK_EFFORT: Record<AiTask, Effort> = { analyze: "low", replies: "medium", refine: "low", coach: "medium" };

const DEFAULT_ROUTES: Record<RouteKey, { model: string; thinking: ThinkingMode; fallback: string | null }> = {
  read_text: { model: SONNET, thinking: "auto", fallback: null },
  read_screenshot: { model: SONNET, thinking: "auto", fallback: null },
  reply_simple: { model: HAIKU, thinking: "auto", fallback: SONNET },
  reply_standard: { model: SONNET, thinking: "auto", fallback: null },
  reply_screenshot: { model: SONNET, thinking: "auto", fallback: null },
  starter: { model: HAIKU, thinking: "auto", fallback: SONNET },
  refine: { model: HAIKU, thinking: "auto", fallback: SONNET },
  tone: { model: HAIKU, thinking: "auto", fallback: SONNET },
  coach_ask: { model: SONNET, thinking: "auto", fallback: null },
  coach_review: { model: SONNET, thinking: "auto", fallback: null },
  coach_practice: { model: SONNET, thinking: "auto", fallback: null },
  coach_advanced: { model: OPUS, thinking: "auto", fallback: null },
};

// ---------------------------------------------------------------- configuration

function env(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value ? value : undefined;
}

function parseEffort(value: string | undefined): Effort | undefined {
  const v = value?.toLowerCase();
  return v === "low" || v === "medium" || v === "high" ? v : undefined;
}

const MODEL_ID = /^claude-[a-z0-9.-]{2,60}$/;

export interface RouteConfigProblem {
  variable: string;
  message: string;
}

/** Parses "model[,effort=..][,thinking=..][,fallback=..]". Unknown parts are reported, not guessed. */
function parseRouteValue(variable: string, raw: string, problems: RouteConfigProblem[]) {
  const [modelPart, ...options] = raw.split(",").map((part) => part.trim());
  const out: { model?: string; effort?: Effort; thinking?: ThinkingMode; fallback?: string | null } = {};
  if (modelPart) {
    if (MODEL_ID.test(modelPart)) out.model = modelPart;
    else problems.push({ variable, message: `"${modelPart.slice(0, 40)}" is not a Claude model id.` });
  }
  for (const option of options) {
    const [key, value = ""] = option.split("=").map((s) => s.trim());
    if (key === "effort") {
      const effort = parseEffort(value);
      if (effort) out.effort = effort;
      else problems.push({ variable, message: `effort must be low, medium or high, not "${value.slice(0, 20)}".` });
    } else if (key === "thinking") {
      if (value === "auto" || value === "off") out.thinking = value;
      else problems.push({ variable, message: `thinking must be auto or off, not "${value.slice(0, 20)}".` });
    } else if (key === "fallback") {
      if (value === "none") out.fallback = null;
      else if (MODEL_ID.test(value)) out.fallback = value;
      else problems.push({ variable, message: `fallback must be a model id or none, not "${value.slice(0, 40)}".` });
    } else if (key) {
      problems.push({ variable, message: `unknown option "${key.slice(0, 20)}".` });
    }
  }
  return out;
}

/**
 * Builds the route table from the environment. Problems are returned (and
 * logged by the caller); a bad value falls back to that route's default
 * rather than stopping the server.
 */
export function resolveRoutes(): { routes: RouteTable; problems: RouteConfigProblem[] } {
  const problems: RouteConfigProblem[] = [];
  const legacy = env("AI_ROUTING")?.toLowerCase() === "off";
  const globalModel = env("AI_MODEL") ?? env("ANTHROPIC_MODEL");
  const globalEffort = parseEffort(env("AI_EFFORT"));

  const routes = {} as RouteTable;
  for (const key of ROUTES) {
    const task = TASK_OF[key];
    const taskModel = env(`AI_MODEL_${task.toUpperCase()}`);
    const effort = parseEffort(env(`AI_EFFORT_${task.toUpperCase()}`)) ?? globalEffort ?? TASK_EFFORT[task];

    if (legacy) {
      const model = taskModel ?? globalModel ?? LEGACY_MODEL;
      routes[key] = {
        model,
        effort,
        thinking: "auto",
        fallback: null,
        source: taskModel ? `AI_MODEL_${task.toUpperCase()}` : globalModel ? "AI_MODEL" : "AI_ROUTING=off",
      };
      continue;
    }

    const variable = `AI_ROUTE_${key.toUpperCase()}`;
    const raw = env(variable);
    const override = raw ? parseRouteValue(variable, raw, problems) : {};
    const base = DEFAULT_ROUTES[key];
    const model = override.model ?? taskModel ?? globalModel ?? base.model;
    const source = override.model ? variable : taskModel ? `AI_MODEL_${task.toUpperCase()}` : globalModel ? "AI_MODEL" : "default";
    // A route forced to another model keeps the default fallback only while it is still the default model.
    const fallback = override.fallback !== undefined ? override.fallback : model === base.model ? base.fallback : null;
    routes[key] = {
      model,
      effort: override.effort ?? effort,
      thinking: override.thinking ?? base.thinking,
      fallback: fallback === model ? null : fallback,
      source,
    };
  }

  for (const key of ROUTES) {
    const route = routes[key];
    if (!knownPrice(route.model)) {
      problems.push({
        variable: `AI_ROUTE_${key.toUpperCase()}`,
        message: `${route.model} is not in the price table, so its spend is estimated at the highest known prices.`,
      });
    }
    if (route.thinking === "off" && thinkingParam(route.model, "off") === undefined) {
      problems.push({
        variable: `AI_ROUTE_${key.toUpperCase()}`,
        message: `${route.model} cannot turn thinking off; it keeps adaptive thinking.`,
      });
    }
  }
  return { routes, problems };
}

/** A route table with one model and effort per task, as before routing. Used by tests and evals. */
export function routesFromTasks(models: Record<AiTask, string>, efforts: Record<AiTask, Effort>): RouteTable {
  const routes = {} as RouteTable;
  for (const key of ROUTES) {
    const task = TASK_OF[key];
    routes[key] = { model: models[task], effort: efforts[task], thinking: "auto", fallback: null, source: "per-task" };
  }
  return routes;
}

/** One line per route, for the start-up log. Model names only. */
export function describeRoutes(routes: RouteTable): string {
  return ROUTES.map((key) => {
    const r = routes[key];
    return `${key}=${r.model}${r.thinking === "off" ? "/thinking-off" : ""}${r.fallback ? `>${r.fallback}` : ""}${r.source === "default" ? "" : ` (${r.source})`}`;
  }).join(" ");
}

// ---------------------------------------------------------------- thinking per model

/**
 * The lowest thinking setting each model accepts, from Anthropic's thinking
 * documentation (checked 13 November 2026):
 *   Sonnet 5.5   {type: "between_tools"} turns off up-front thinking ("disabled" is a 400)
 *   Haiku 5.5    {type: "disabled"}
 *   Opus 5, Sonnet 5, Haiku 4.5   {type: "disabled"}
 *   Opus 5.5, Fable   cannot be turned off; the parameter is left out
 * Only valid at effort high or below, which is all ReplyRight uses.
 */
const THINKING_OFF: [string, BetaThinkingConfigParam][] = [
  ["claude-sonnet-5-5", { type: "between_tools" }],
  ["claude-haiku-5-5", { type: "disabled" }],
  ["claude-haiku-4-5", { type: "disabled" }],
  ["claude-sonnet-5", { type: "disabled" }],
  ["claude-opus-5", { type: "disabled" }],
];

/** The same model, or a dated snapshot of it (claude-opus-5-20260101). Never a newer model with a longer name. */
function sameModel(model: string, name: string): boolean {
  return model === name || new RegExp(`^${name.replace(/[.]/g, "\\.")}-\\d{8}$`).test(model);
}

export function thinkingParam(model: string, mode: ThinkingMode): BetaThinkingConfigParam | undefined {
  if (mode === "auto") return undefined;
  for (const [name, param] of THINKING_OFF) {
    if (sameModel(model, name)) return param;
  }
  return undefined;
}

// ---------------------------------------------------------------- choosing a route

/** Refine actions that change the tone of a message rather than edit it. */
export const TONE_ACTIONS = new Set(["flirty", "playful", "charming", "subtle", "warm"]);

const DEFAULT_SIMPLE_INTENTS = ["natural", "keep_going"];
const DEFAULT_SIMPLE_MAX_CHARS = 600;
const SIMPLE_MAX_LINES = 10;

export interface SimpleReplyRule {
  enabled: boolean;
  intents: Set<string>;
  maxChars: number;
}

/**
 * When a reply counts as simple, and goes to the fast route:
 *   AI_SIMPLE_REPLIES=off             never (every reply is standard)
 *   AI_SIMPLE_REPLY_INTENTS           intents that may be simple. Default natural,keep_going
 *   AI_SIMPLE_REPLY_MAX_CHARS         longest conversation that may be simple. Default 600
 * It is a fixed rule on the request, not a model call, so it adds no cost or delay.
 */
export function simpleReplyRule(): SimpleReplyRule {
  const intents = env("AI_SIMPLE_REPLY_INTENTS")
    ?.split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const max = Number(env("AI_SIMPLE_REPLY_MAX_CHARS"));
  return {
    enabled: env("AI_SIMPLE_REPLIES")?.toLowerCase() !== "off",
    intents: new Set(intents && intents.length > 0 ? intents : DEFAULT_SIMPLE_INTENTS),
    maxChars: Number.isFinite(max) && max > 0 ? max : DEFAULT_SIMPLE_MAX_CHARS,
  };
}

/**
 * A reply is simple when it is a plain answer to a short text conversation:
 * no screenshots, a light intent (natural or keep it going by default), no
 * special instruction, and at most ten lines and 600 characters of
 * conversation. Everything else, including flirting, asking out, feelings and
 * boundaries, is standard.
 */
export function isSimpleReply(input: RepliesRequest, images: TransientImage[], rule = simpleReplyRule()): boolean {
  if (!rule.enabled || input.kind !== "reply" || images.length > 0) return false;
  if (!rule.intents.has(input.intent)) return false;
  if (input.instruction.trim().length > 0) return false;
  const lines = input.transcript.length > 0 ? input.transcript.map((line) => line.text) : input.conversation.split("\n");
  const chars = lines.reduce((sum, line) => sum + line.length, 0);
  return lines.filter((line) => line.trim()).length <= SIMPLE_MAX_LINES && chars <= rule.maxChars;
}

export interface CallDescription {
  /** What the request was for, as the usage ledger records it. */
  feature: string;
  /** Which route (model policy) serves it. */
  route: RouteKey;
}

/** The single place that turns a validated request into a feature label and a route. */
export function describeCall(task: AiTask, input: unknown, images: TransientImage[]): CallDescription {
  switch (task) {
    case "analyze":
      return images.length > 0 ? { feature: "read_screenshot", route: "read_screenshot" } : { feature: "read_text", route: "read_text" };
    case "replies": {
      const request = input as RepliesRequest;
      if (request.kind === "starter") return { feature: "starter", route: "starter" };
      if (images.length > 0) return { feature: "replies_from_screenshot", route: "reply_screenshot" };
      const route: RouteKey = isSimpleReply(request, images) ? "reply_simple" : "reply_standard";
      return { feature: request.avoid.length > 0 ? "regenerate" : "replies", route };
    }
    case "refine": {
      const request = input as RefineRequest;
      return TONE_ACTIONS.has(request.action) ? { feature: "tone", route: "tone" } : { feature: "refine", route: "refine" };
    }
    case "coach": {
      const request = input as CoachRequest;
      if (request.depth === "deep") return { feature: `coach_${request.mode}_deep`, route: "coach_advanced" };
      const route: RouteKey = request.mode === "review" ? "coach_review" : request.mode === "practice" ? "coach_practice" : "coach_ask";
      return { feature: `coach_${request.mode}`, route };
    }
  }
}
