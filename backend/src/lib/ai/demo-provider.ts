import "server-only";
import type {
  Analysis,
  AnalyzeRequest,
  CoachRequest,
  CoachResult,
  RefineRequest,
  RefineResult,
  RepliesRequest,
  RepliesResult,
  Suggestion,
  TranscriptLine,
} from "@/lib/domain/contracts";
import type { Intent } from "@/lib/domain/intents";
import type { AiProvider, TransientImage } from "./types";

/**
 * Demo provider used when no AI credentials are configured.
 *
 * It does NOT read conversations or screenshots and does NOT rewrite text.
 * It returns fixed, pre-written samples so every screen can be explored end to
 * end. Responses carry `mode: "demo"`, and every string a user could mistake
 * for analysis says that it is a sample.
 */
const s = (style: string, text: string, why: string): Suggestion => ({ style, text, why: `Sample: ${why}` });

const SAMPLES: Record<Intent, Suggestion[]> = {
  natural: [
    s("Most natural", "haha fair. how's your week going so far?", "relaxed and easy to answer."),
    s("Warm", "that actually made me smile. what are you up to today?", "shows it landed and keeps things moving."),
    s("A bit playful", "ok I need the full story behind that", "invites them to share more."),
    s("Most natural", "honestly same. what's the plan for the weekend?", "agrees, then opens a new thread."),
    s("Curious", "wait, tell me more about that", "simple curiosity is easy to respond to."),
    s("Light", "that sounds like a good day to me", "low-key and warm."),
  ],
  flirt: [
    s("Flirty", "ok that's actually really cute, you're making it hard to play it cool", "open about interest while staying light."),
    s("Playful", "careful, keep talking like that and I'll have to take you out", "turns banter into a soft invitation."),
    s("More direct", "I'm smiling at my phone and it's your fault", "honest and a little bold."),
    s("Soft tease", "bold of you to be this charming on a weekday", "a compliment wrapped in a tease."),
    s("Warm", "you have a very specific talent for making my day better", "sincere and easy to receive."),
    s("Flirty", "this would be a much better conversation in person", "hints at meeting without pressure."),
  ],
  laugh: [
    s("Playful", "so you're telling me you've NEVER had a bad pizza take? suspicious", "light teasing that invites them to play along."),
    s("Silly", "important question: if we got stuck in a lift, who panics first", "an easy, fun question."),
    s("Mock serious", "wow. I'm going to need a minute to recover from that", "playful exaggeration keeps the energy up."),
    s("Running joke", "adding this to the list of reasons I can't trust your judgement", "starts a joke you can build on."),
    s("Quick game", "ok rapid fire. sunrise or sunset, coffee or tea, chaos or plans", "gives them something quick to answer."),
    s("Dry", "noted. I'll allow it", "understated humour."),
  ],
  interest: [
    s("Curious", "wait, I want the full story behind that. how did you end up there?", "genuine curiosity makes people open up."),
    s("Attentive", "you mentioned your sister earlier. are you two close?", "shows you were listening."),
    s("Warm", "that's really cool actually. what got you into it?", "interest in them, not just the topic."),
    s("Specific", "ok what's the best thing you've eaten there, I need a recommendation", "asks about something they clearly like."),
    s("Light", "I feel like there's a story there", "leaves a door open."),
    s("Direct", "I like hearing you talk about this", "says it plainly."),
  ],
  confident: [
    s("Direct", "I like talking to you. let's get a coffee this week", "clear about interest and about the plan."),
    s("Relaxed", "strong take, but I'm going to need you to defend it in person", "sure of itself without overexplaining."),
    s("Simple", "honestly that's the best thing I've heard all week", "short, warm, no hedging."),
    s("Calm", "no stress at all. let me know when things settle down", "secure and pressure-free."),
    s("Honest", "I'll be honest, I was hoping you'd text", "open in a confident way."),
    s("Clear", "I'd rather hear this in person. saturday?", "moves things forward calmly."),
  ],
  keep_going: [
    s("Easy question", "ok I'm curious now, what's the best thing you've eaten lately", "simple to answer and leads somewhere."),
    s("New thread", "random, but what's something you're looking forward to this month", "opens a fresh topic."),
    s("Opinion bait", "settle something for me: is a hot dog a sandwich", "a small debate is easy to join."),
    s("Callback", "still thinking about that story you told me lol", "brings back something that worked."),
    s("Light", "sounds like a good weekend. anything fun coming up?", "relaxed and open-ended."),
    s("Playful", "ok your turn, tell me something I don't know about you", "hands them the next move."),
  ],
  mysterious: [
    s("Teasing", "I have a theory about you but I'm not ready to share it yet", "invites curiosity."),
    s("Playful", "that's a story for when I know you better", "leaves something for later."),
    s("Light", "maybe. you'll have to find out", "short and intriguing."),
    s("Hinting", "I could tell you, but it's better in person", "points towards meeting."),
    s("Dry", "no comment. yet", "understated."),
    s("Warm", "there's more to that story, remind me to tell you", "mystery without coldness."),
  ],
  charming: [
    s("Attentive", "you have a really good way of making ordinary things sound interesting", "specific praise feels sincere."),
    s("Warm", "talking to you is genuinely the nicest part of my day", "simple and heartfelt."),
    s("Thoughtful", "hope the big day went well, I was thinking about it", "attentive without being intense."),
    s("Light", "you always have the best recommendations", "a small, easy compliment."),
    s("Curious", "that's exactly the kind of place I'd love. you'll have to show me", "connects their world to yours."),
    s("Playful", "I was having an average day and then you texted", "charming with a wink."),
  ],
  ask_out: [
    s("Low-pressure", "this would be a much better conversation over a coffee. free this week?", "specific and easy to say yes or no to."),
    s("Playful", "ok we clearly need to settle this in person. drinks thursday?", "grows out of the banter."),
    s("Direct", "I'd like to take you out. are you around saturday?", "clear and confident."),
    s("Casual", "I'm checking out that ramen place this weekend, want to come?", "an invitation to join a plan."),
    s("Warm", "I'm enjoying this a lot. would you want to meet up sometime soon?", "sincere and open."),
    s("Light", "we should continue this somewhere with snacks", "keeps it fun."),
  ],
  dry_reply: [
    s("New angle", "ok change of subject. what's the best part of your week so far", "resets the energy without calling it out."),
    s("Playful", "I'll take that as a strong maybe", "light and unbothered."),
    s("Unbothered", "fair enough. hope the day gets better", "brief, kind, no chasing."),
    s("Fun question", "quick one: beach or mountains", "something tiny to answer."),
    s("Warm", "sounds like a long day. I'll leave you to it, talk later?", "gives them room."),
    s("Humour", "riveting. tell me more", "teases gently."),
  ],
  feelings: [
    s("Honest", "I really like talking to you. just wanted to say that", "simple and sincere."),
    s("Warm", "I've been thinking about you more than I expected to", "open without pressure."),
    s("Gentle", "no pressure at all, but I'm enjoying getting to know you", "leaves them room."),
    s("Direct", "I like you. thought you should know", "clear and brave."),
    s("Light", "you've become my favourite notification", "affection with a smile."),
    s("Thoughtful", "I had a really good time with you. I'd like to do that again", "specific and forward-looking."),
  ],
  boundary: [
    s("Clear and kind", "I'd rather take things a bit slower. I'm enjoying getting to know you though", "states the limit and the warmth."),
    s("Direct", "that's not really my thing, but I'm happy to keep talking", "firm without blame."),
    s("Gentle", "I'm not comfortable with that. can we talk about something else?", "simple and respectful."),
    s("Warm", "I like you, and I also need a little space today", "both things are true."),
    s("Calm", "I'd prefer not to share that yet", "no apology needed."),
    s("Honest", "I don't love that joke. I'd rather we didn't go there", "clear and calm."),
  ],
};

const STARTERS: Suggestion[] = [
  s("Easy opener", "hey, I have to ask about the photo with the dog. is there a story?", "specific openers get better answers."),
  s("Playful", "ok serious question to start: best pizza topping. choose wisely", "low-stakes and fun."),
  s("Direct", "hi. you seem like someone I'd like to talk to", "honest and simple."),
  s("Curious", "what's the best thing that's happened to you this week?", "positive and open-ended."),
  s("Light", "I'm terrible at openers so I'll just say hi and hope for the best", "disarming honesty."),
  s("Callback", "it's been a minute. how did that trip end up going?", "a natural way to restart."),
];

function pickFresh(pool: Suggestion[], avoid: string[], count: number): Suggestion[] {
  const fresh = pool.filter((item) => !avoid.includes(item.text));
  return (fresh.length >= count ? fresh : pool).slice(0, count);
}

function parsePastedConversation(text: string): TranscriptLine[] {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, 40)
    .map((line): TranscriptLine => {
      const match = /^(them|me|you|i)\s*:\s*(.+)$/i.exec(line);
      if (!match) return { speaker: "unknown", text: line };
      const who = match[1].toLowerCase();
      return { speaker: who === "them" ? "them" : "me", text: match[2] };
    });
}

export class DemoProvider implements AiProvider {
  readonly id = "demo";
  readonly mode = "demo" as const;
  readonly supportsImages = false;

  modelFor(): null {
    return null;
  }

  private async pause() {
    // Short delay so loading states are visible while exploring the demo.
    const delay = Number(process.env.DEMO_DELAY_MS ?? 600);
    if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay));
  }

  async analyze({ request, images }: { request: AnalyzeRequest; images: TransientImage[] }): Promise<Analysis> {
    await this.pause();
    // Splitting pasted text on "Them:" / "Me:" labels is plain parsing, not analysis.
    const transcript = request.conversation ? parsePastedConversation(request.conversation) : [];
    const lastThem = [...transcript].reverse().find((line) => line.speaker === "them");
    const shared =
      images.length > 0 ? `${images.length} screenshot${images.length > 1 ? "s" : ""}` : "your messages";
    return {
      canReply: true,
      transcript,
      latestMessage: lastThem?.text ?? null,
      latestFromMe: transcript.length > 0 && transcript[transcript.length - 1].speaker === "me",
      read: `Demo mode: no AI is connected, so I haven't actually read ${shared}. With AI on, you'd get a short, friendly take on the conversation here.`,
      toneLabel: "Not analysed (demo)",
      observations: ["Sample: things that are plainly visible in the messages are listed here."],
      assumptions: ["Sample: things nobody can know from a text, phrased as possibilities, are listed here."],
      opportunity: "Sample: a suggested angle for your next message appears here.",
      suggestedIntents: ["natural", "laugh", "flirt"],
      headsUp: null,
      problem: "none",
    };
  }

  async replies({ request, images }: { request: RepliesRequest; images: TransientImage[] }): Promise<RepliesResult> {
    await this.pause();
    const pool = request.kind === "starter" && request.intent === "natural" ? STARTERS : SAMPLES[request.intent];
    const ignored: string[] = [];
    if (images.length) ignored.push("screenshots");
    if (request.instruction) ignored.push("your instruction");
    if (request.draft) ignored.push("your draft");
    return {
      note: "Demo mode: these are pre-written samples, not replies to your conversation.",
      replies: pickFresh(pool, request.avoid, 3),
      headsUp: ignored.length
        ? `In demo mode ${ignored.join(", ")} ${ignored.length > 1 ? "are" : "is"} not used. Connect an AI provider on the server for real replies.`
        : null,
    };
  }

  async refine({ request }: { request: RefineRequest }): Promise<RefineResult> {
    await this.pause();
    const pool: Suggestion[] = [
      s("Sample rewrite", "haha ok that's fair. what are you up to later?", "a real rewrite of your message appears here."),
      s("Sample rewrite", "honestly that made my day. tell me more", "a second take appears here."),
      s("Sample rewrite", "noted. I'm into it", "a third take appears here."),
    ];
    return {
      options: pool.slice(0, request.count),
      note: "Demo mode: this is a pre-written sample, not a rewrite of your message.",
    };
  }

  async coach({ request }: { request: CoachRequest }): Promise<CoachResult> {
    await this.pause();
    const base: CoachResult = {
      message:
        "Demo mode: the coach needs an AI provider connected on the server, so this is a pre-written sample rather than an answer to your question. With AI on, you'd get a direct, practical answer here with the reasoning behind it.",
      suggestions: [
        { label: "Sample line", text: "this would be a much better conversation over a coffee. free this week?" },
      ],
      followUps: ["Is it too soon to suggest meeting?", "Does my reply sound too eager?"],
      lesson: "Sample: one small takeaway to remember appears here.",
      review: null,
      practice: null,
      headsUp: null,
    };

    if (request.mode === "review") {
      return {
        ...base,
        message:
          "Demo mode: no AI is connected, so I haven't read your message. This is what a review looks like, filled with sample text.",
        suggestions: [],
        followUps: ["How do I sound less eager?", "Is this too long?"],
        review: {
          intent: "Sample: what you are trying to say appears here.",
          comesAcross: "Sample: how the message could read to the person receiving it appears here.",
          checks: [
            { aspect: "natural", verdict: "good", note: "Sample: whether it sounds like a real text." },
            { aspect: "intensity", verdict: "watch", note: "Sample: whether it comes on too strong." },
            { aspect: "formality", verdict: "good", note: "Sample: whether it reads as stiff." },
            { aspect: "feeling", verdict: "good", note: "Sample: whether it carries the feeling you intend." },
            { aspect: "clarity", verdict: "watch", note: "Sample: whether it could be misunderstood." },
          ],
          improvements: ["Sample: a concrete improvement appears here."],
          alternative: "this is a sample alternative, not a rewrite of your message",
          whyItWorks: "Sample: why the alternative works appears here.",
          lesson: "Sample: one small takeaway to remember appears here.",
        },
      };
    }

    if (request.mode === "practice") {
      const opening = request.messages.length === 0;
      return {
        ...base,
        message: opening
          ? "Demo mode: no AI is connected, so this practice partner only sends pre-written sample lines and cannot react to what you write."
          : "Demo mode: this is a pre-written sample reply, not a reaction to your message.",
        suggestions: [],
        followUps: ["Try a different scenario", "What makes a good first message?"],
        lesson: null,
        practice: {
          partnerReply: opening ? "hey! how's your week going?" : "haha ok fair. what about you?",
          feedback: opening ? null : "Sample: feedback on the message you just sent appears here.",
          tryThis: null,
          finished: false,
        },
      };
    }

    return base;
  }
}
