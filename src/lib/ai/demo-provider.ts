import "server-only";
import type { ReplyResult, ReplySuggestion } from "@/lib/domain/replies";
import type { Tone } from "@/lib/domain/tones";
import type { GenerateRepliesInput, ReplyProvider } from "./types";

/**
 * Demo provider used when no AI credentials are configured.
 *
 * It does NOT read the conversation or the screenshots. It returns fixed,
 * pre-written samples so the interface can be explored end to end. The API
 * response is marked `mode: "demo"` and the UI labels every result as a sample.
 */
const SAMPLES: Record<Tone, ReplySuggestion[]> = {
  flirty: [
    { label: "Warm callback", text: "ok that's actually really cute, you're making it hard to play it cool over here", why: "Sample: shows interest openly while keeping it light." },
    { label: "Playful challenge", text: "careful, keep talking like that and I'll have to take you out to prove you wrong", why: "Sample: turns banter into a soft invitation." },
    { label: "Easy compliment", text: "you have a very specific talent for making my day better", why: "Sample: a sincere compliment that's easy to receive." },
    { label: "Lean in", text: "I'm smiling at my phone like an idiot and it's your fault", why: "Sample: honest and a little bold." },
    { label: "Soft tease", text: "bold of you to be this charming on a weekday", why: "Sample: a compliment wrapped in a tease." },
    { label: "Move it forward", text: "this would be a much better conversation over a drink. thursday?", why: "Sample: a clear, low-pressure next step." },
  ],
  confident: [
    { label: "Clear plan", text: "I like talking to you. let's get a coffee this week, are you free thursday?", why: "Sample: direct about interest and specific about the plan." },
    { label: "Own the opinion", text: "strong take, but I'm going to need you to defend it in person", why: "Sample: relaxed and sure without overexplaining." },
    { label: "Simple and sure", text: "honestly that's the best thing I've heard all week", why: "Sample: short, warm, no hedging." },
    { label: "Straight ask", text: "I'd rather hear this story in person. saturday afternoon work for you?", why: "Sample: moves things forward calmly." },
    { label: "Calm reset", text: "no stress at all. let me know when things settle down, I'd still like to see you", why: "Sample: secure and pressure-free." },
    { label: "Easy honesty", text: "I'll be honest, I was hoping you'd text", why: "Sample: vulnerable in a confident way." },
  ],
  playful: [
    { label: "Teasing callback", text: "so you're telling me you've NEVER had a bad pizza take? suspicious", why: "Sample: light teasing that invites them to play along." },
    { label: "Silly hypothetical", text: "important question: if we were stuck in a lift, who's panicking first", why: "Sample: an easy, fun question to answer." },
    { label: "Mock outrage", text: "wow. I'm going to need a minute to recover from that", why: "Sample: playful exaggeration keeps the energy up." },
    { label: "Running joke", text: "adding this to the list of reasons I can't trust your judgement", why: "Sample: starts a running joke you can build on." },
    { label: "Game on", text: "ok rapid fire. sunrise or sunset, coffee or tea, chaos or plans", why: "Sample: gives them something fun and quick to reply to." },
    { label: "Fake formal", text: "your application to be my favourite person has been received and is under review", why: "Sample: silly, warm and a bit flirty." },
  ],
  charming: [
    { label: "Notice the detail", text: "the way you talk about your sister is really sweet. are you two close?", why: "Sample: shows you were actually listening." },
    { label: "Curious follow-up", text: "wait, I want the full story behind that. how did you end up there?", why: "Sample: genuine curiosity makes people open up." },
    { label: "Thoughtful compliment", text: "you have a really good way of making ordinary things sound interesting", why: "Sample: specific praise feels more sincere." },
    { label: "Shared moment", text: "that's exactly the kind of place I'd love. you'll have to show me sometime", why: "Sample: connects their world to yours." },
    { label: "Warm check-in", text: "hope the big day went well, I was thinking about it", why: "Sample: attentive without being intense." },
    { label: "Honest warmth", text: "talking to you is genuinely the nicest part of my day", why: "Sample: sincere and simple." },
  ],
  subtle: [
    { label: "Low-key reply", text: "haha fair. how's your week going so far?", why: "Sample: casual, easy to respond to." },
    { label: "Light hook", text: "that sounds fun. I've been meaning to try that place", why: "Sample: leaves a natural opening without pressure." },
    { label: "Easy question", text: "ok I'm curious now, what's the best thing you've eaten lately", why: "Sample: keeps the conversation flowing gently." },
    { label: "Quiet interest", text: "you always have the best recommendations", why: "Sample: interest is implied, not declared." },
    { label: "Keep it open", text: "sounds like a good weekend. anything fun coming up?", why: "Sample: relaxed and open-ended." },
    { label: "Soft callback", text: "still thinking about that story you told me lol", why: "Sample: shows they're on your mind, quietly." },
  ],
};

export class DemoReplyProvider implements ReplyProvider {
  readonly id = "demo";
  readonly mode = "demo" as const;
  readonly model = null;
  readonly supportsImages = false;

  async generateReplies({ request, images }: GenerateRepliesInput): Promise<ReplyResult> {
    // Small delay so loading states are visible while exploring the demo.
    await new Promise((resolve) => setTimeout(resolve, 700));

    const pool = SAMPLES[request.tone];
    const fresh = pool.filter((s) => !request.avoid.includes(s.text));
    const source = fresh.length >= 3 ? fresh : pool;
    const replies = source.slice(0, 3);

    const inputs: string[] = [];
    if (images.length) inputs.push(`${images.length} screenshot${images.length > 1 ? "s" : ""}`);
    if (request.conversation) inputs.push("your pasted messages");

    return {
      read: {
        summary: `Demo mode: no AI model is configured, so ReplyRight did not read ${inputs.join(" or ") || "your conversation"}. These are pre-written ${request.tone} samples that show how results look.`,
        vibe: "Not analysed in demo mode",
        cues: [],
      },
      transcript: [],
      replies,
      headsUp: request.instruction
        ? `Your instruction ("${request.instruction}") is only applied when an AI provider is configured.`
        : null,
    };
  }
}
