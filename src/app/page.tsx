import Link from "next/link";
import { Logo } from "@/components/brand/Logo";
import { ButtonLink, Card, Eyebrow } from "@/components/ui/primitives";
import { TONE_DEFINITIONS, TONES } from "@/lib/domain/tones";

const TONE_EXAMPLES: Record<(typeof TONES)[number], string> = {
  flirty: "careful, keep talking like that and I'll have to take you out",
  confident: "I like talking to you. coffee on thursday?",
  playful: "so you've NEVER had a bad pizza take? suspicious",
  charming: "wait, I want the full story behind that",
  subtle: "haha fair. how's your week going so far?",
};

const STEPS = [
  {
    n: "01",
    title: "Share the moment",
    body: "Drop in a screenshot or paste the last few messages. Nothing connects to your apps.",
  },
  {
    n: "02",
    title: "Choose your energy",
    body: "Pick a tone and, if you like, add a nudge such as “make it less eager” or “make them laugh”.",
  },
  {
    n: "03",
    title: "Pick, tweak, send",
    body: "Get three different directions. Edit any of them, regenerate, copy, and send it yourself.",
  },
];

const PRINCIPLES = [
  {
    title: "Options, not scripts",
    body: "There’s no single perfect reply. You get three genuinely different directions and you decide.",
  },
  {
    title: "No mind-reading",
    body: "ReplyRight describes how a message might come across. It never claims to know what someone feels.",
  },
  {
    title: "No games",
    body: "No negging, pressure or manipulation tactics. If someone sets a boundary, the suggestions respect it.",
  },
  {
    title: "Still you",
    body: "Your communication profile keeps replies in your language, your humour and your way of texting.",
  },
];

export default function LandingPage() {
  return (
    <div className="relative overflow-x-clip">
      <div className="glow pointer-events-none absolute inset-x-0 top-0 h-[720px]" aria-hidden />
      <div className="grain pointer-events-none absolute inset-0" aria-hidden />

      <header className="relative mx-auto flex max-w-6xl items-center justify-between px-5 pt-[max(env(safe-area-inset-top),1.25rem)] pb-4 sm:px-8">
        <Logo />
        <nav className="flex items-center gap-1 sm:gap-2">
          <a href="#how" className="hidden rounded-full px-3 py-2 text-sm text-muted hover:text-fg sm:block">
            How it works
          </a>
          <Link href="/privacy" className="hidden rounded-full px-3 py-2 text-sm text-muted hover:text-fg sm:block">
            Privacy
          </Link>
          <ButtonLink href="/app" size="sm">
            Open app
          </ButtonLink>
        </nav>
      </header>

      <main className="relative">
        {/* Hero */}
        <section className="mx-auto grid max-w-6xl items-center gap-14 px-5 pt-12 pb-20 sm:px-8 lg:grid-cols-[1.1fr_1fr] lg:pt-20 lg:pb-28">
          <div className="animate-rise">
            <span className="inline-flex items-center gap-2 rounded-full border border-line bg-surface/70 px-3 py-1 text-xs text-muted">
              <span className="size-1.5 rounded-full bg-accent" />
              Your dating communication assistant
            </span>
            <h1 className="mt-6 font-display text-[3.4rem] leading-[0.95] tracking-tight sm:text-7xl lg:text-[5.5rem]">
              Say it better.
              <br />
              <em className="text-accent">Be yourself.</em>
            </h1>
            <p className="mt-6 max-w-md text-[17px] leading-relaxed text-muted">
              Stuck on what to text back? Share the conversation, choose your vibe, and get three natural replies that
              sound confident, warm and unmistakably you.
            </p>
            <div className="mt-9 flex flex-wrap items-center gap-3">
              <ButtonLink href="/app" size="lg">
                Write a reply
                <Arrow />
              </ButtonLink>
              <ButtonLink href="#how" variant="ghost" size="lg">
                See how it works
              </ButtonLink>
            </div>
            <p className="mt-6 text-xs text-faint">Screenshots are processed in memory and never stored.</p>
          </div>

          <HeroPreview />
        </section>

        {/* How it works */}
        <section id="how" className="mx-auto max-w-6xl scroll-mt-10 px-5 py-20 sm:px-8">
          <Eyebrow>How it works</Eyebrow>
          <h2 className="mt-3 max-w-xl font-display text-4xl leading-tight sm:text-5xl">
            From “uh, what now?” to sent, in under a minute.
          </h2>
          <div className="mt-12 grid gap-4 md:grid-cols-3">
            {STEPS.map((step) => (
              <Card key={step.n} className="p-6">
                <span className="font-display text-3xl text-accent italic">{step.n}</span>
                <h3 className="mt-6 text-lg font-medium">{step.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted">{step.body}</p>
              </Card>
            ))}
          </div>
        </section>

        {/* Tones */}
        <section className="mx-auto max-w-6xl px-5 py-20 sm:px-8">
          <div className="flex flex-wrap items-end justify-between gap-6">
            <div>
              <Eyebrow>Five tones</Eyebrow>
              <h2 className="mt-3 max-w-lg font-display text-4xl leading-tight sm:text-5xl">
                Same you, <em className="text-accent">different energy.</em>
              </h2>
            </div>
            <p className="max-w-sm text-sm leading-relaxed text-muted">
              Choose how you want to come across. ReplyRight adapts the reply and keeps your voice.
            </p>
          </div>
          <div className="no-scrollbar -mx-5 mt-10 flex snap-x gap-3 overflow-x-auto px-5 pb-2 sm:mx-0 sm:grid sm:grid-cols-2 sm:overflow-visible sm:px-0 lg:grid-cols-5">
            {TONES.map((tone) => (
              <Card key={tone} className="w-64 shrink-0 snap-start p-5 sm:w-auto">
                <p className="text-sm font-medium">{TONE_DEFINITIONS[tone].label}</p>
                <p className="text-xs text-faint">{TONE_DEFINITIONS[tone].hint}</p>
                <p className="mt-6 rounded-2xl rounded-br-md bg-accent-strong/90 px-3.5 py-2.5 text-[13px] leading-snug text-white">
                  {TONE_EXAMPLES[tone]}
                </p>
              </Card>
            ))}
          </div>
        </section>

        {/* Principles */}
        <section className="mx-auto max-w-6xl px-5 py-20 sm:px-8">
          <Eyebrow>What we believe</Eyebrow>
          <h2 className="mt-3 max-w-xl font-display text-4xl leading-tight sm:text-5xl">
            Built for real connection, not tricks.
          </h2>
          <div className="mt-12 grid gap-px overflow-hidden rounded-3xl border border-line bg-line sm:grid-cols-2">
            {PRINCIPLES.map((p) => (
              <div key={p.title} className="bg-ink p-7">
                <h3 className="text-base font-medium">{p.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted">{p.body}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Privacy */}
        <section className="mx-auto max-w-6xl px-5 py-20 sm:px-8">
          <Card className="relative overflow-hidden p-8 sm:p-12">
            <div className="glow pointer-events-none absolute inset-0 opacity-60" aria-hidden />
            <div className="relative grid gap-10 lg:grid-cols-2">
              <div>
                <Eyebrow>Privacy</Eyebrow>
                <h2 className="mt-3 font-display text-4xl leading-tight sm:text-5xl">Your conversations stay yours.</h2>
                <Link href="/privacy" className="mt-6 inline-flex items-center gap-1.5 text-sm text-accent hover:underline">
                  Read how we handle data <Arrow />
                </Link>
              </div>
              <ul className="space-y-5 text-sm leading-relaxed text-muted">
                <PrivacyPoint title="Screenshots aren’t stored">
                  They’re resized on your device, processed in memory to write your replies, then discarded.
                </PrivacyPoint>
                <PrivacyPoint title="Your profile lives on your device">
                  Tone, language and style preferences are saved in your browser, not on our servers.
                </PrivacyPoint>
                <PrivacyPoint title="We never touch your apps">
                  ReplyRight doesn’t connect to or scrape WhatsApp, Instagram, Tinder or anything else. You choose what to share.
                </PrivacyPoint>
              </ul>
            </div>
          </Card>
        </section>

        {/* Final CTA */}
        <section className="mx-auto max-w-6xl px-5 pt-10 pb-24 text-center sm:px-8">
          <h2 className="font-display text-5xl leading-tight sm:text-6xl">
            Your move. <em className="text-accent">Make it count.</em>
          </h2>
          <ButtonLink href="/app" size="lg" className="mt-8">
            Write a reply
            <Arrow />
          </ButtonLink>
        </section>
      </main>

      <footer className="relative border-t border-line">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-5 py-8 text-xs text-faint sm:flex-row sm:items-center sm:justify-between sm:px-8">
          <p>© ReplyRight. For adults 18+. Suggestions are options, not promises.</p>
          <div className="flex gap-5">
            <Link href="/privacy" className="hover:text-fg">Privacy</Link>
            <Link href="/app" className="hover:text-fg">App</Link>
          </div>
        </div>
      </footer>
    </div>
  );
}

function PrivacyPoint({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <li className="flex gap-3">
      <span className="mt-1 flex size-5 shrink-0 items-center justify-center rounded-full bg-accent-soft text-accent">
        <svg viewBox="0 0 16 16" className="size-3" fill="none" aria-hidden>
          <path d="M3.5 8.5l3 3 6-6.5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
      <span>
        <span className="block font-medium text-fg">{title}</span>
        {children}
      </span>
    </li>
  );
}

function Arrow() {
  return (
    <svg viewBox="0 0 16 16" className="size-4" fill="none" aria-hidden>
      <path d="M3 8h10m-4-4 4 4-4 4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function HeroPreview() {
  return (
    <div className="relative mx-auto w-full max-w-sm animate-rise [animation-delay:120ms] lg:max-w-md">
      <div className="absolute -inset-8 rounded-[3rem] bg-accent-strong/20 blur-3xl" aria-hidden />
      <Card className="relative p-5 shadow-2xl shadow-black/60 sm:p-6">
        <div className="flex items-center justify-between">
          <Eyebrow>Example</Eyebrow>
          <span className="rounded-full border border-line px-2.5 py-0.5 text-[11px] text-muted">Playful</span>
        </div>

        <div className="mt-5 space-y-2">
          <p className="w-fit max-w-[80%] rounded-2xl rounded-bl-md bg-surface-3 px-3.5 py-2.5 text-[13px] leading-snug">
            ok be honest, is pineapple on pizza a dealbreaker for you
          </p>
          <p className="ml-auto w-fit max-w-[70%] rounded-2xl rounded-br-md bg-surface-2 px-3.5 py-2.5 text-[13px] leading-snug text-muted">
            depends who&apos;s asking 👀
          </p>
          <p className="w-fit max-w-[80%] rounded-2xl rounded-bl-md bg-surface-3 px-3.5 py-2.5 text-[13px] leading-snug">
            me. I&apos;m asking. and I already ordered one
          </p>
        </div>

        <div className="mt-6 space-y-2.5">
          {[
            ["Mock outrage", "wow. and here I was about to say you had great taste"],
            ["Playful deal", "fine, but you're explaining yourself over a slice this weekend"],
            ["Easy tease", "bold of you to admit that this early"],
          ].map(([label, text], i) => (
            <div
              key={label}
              className="animate-rise rounded-2xl border border-line bg-surface-2/70 p-3.5"
              style={{ animationDelay: `${300 + i * 120}ms` }}
            >
              <p className="text-[11px] font-medium text-accent">{label}</p>
              <p className="mt-1 text-[13px] leading-snug">{text}</p>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}
