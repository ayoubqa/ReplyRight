import type { Metadata } from "next";
import { Logo } from "@/components/brand/Logo";
import { ButtonLink, Eyebrow } from "@/components/ui/primitives";

export const metadata: Metadata = { title: "Privacy" };

const SECTIONS = [
  {
    title: "Screenshots are processed, not stored",
    body: [
      "When you add a screenshot, your browser resizes it and re-encodes it as a new image, which also removes hidden metadata such as location.",
      "The image is sent to our server over HTTPS, held in memory only for the length of that single request, and forwarded to the AI provider to read the conversation. We do not write it to disk, save it to a database, or log its contents. Once your replies are returned, it is discarded.",
    ],
  },
  {
    title: "Pasted messages work the same way",
    body: [
      "Text you paste is used to write that set of replies and is not saved by ReplyRight. It isn’t kept in your browser after you leave the page either.",
    ],
  },
  {
    title: "Your profile stays on your device",
    body: [
      "Your communication profile (tone, language, humour, length, emoji and style notes) is saved in your browser’s local storage. It is sent along with each request so replies sound like you, but we don’t store it on our servers.",
    ],
  },
  {
    title: "AI providers",
    body: [
      "When an AI provider is configured, conversation content is sent to that provider (currently Anthropic) to generate suggestions, under the provider’s API terms and data retention policy. Without a provider, ReplyRight runs in a clearly labelled demo mode and nothing is sent anywhere.",
    ],
  },
  {
    title: "We never access your apps",
    body: [
      "ReplyRight does not connect to, log in to, or scrape WhatsApp, Instagram, Tinder, Hinge or any other app. You decide exactly what to share, and you send messages yourself.",
    ],
  },
  {
    title: "Be kind to the other person",
    body: [
      "Screenshots include someone else’s words. Share only what you need, and consider cropping out names, photos and phone numbers.",
    ],
  },
];

export default function PrivacyPage() {
  return (
    <div className="relative">
      <div className="glow pointer-events-none absolute inset-x-0 top-0 h-[420px] opacity-70" aria-hidden />
      <header className="relative mx-auto flex max-w-3xl items-center justify-between px-5 pt-[max(env(safe-area-inset-top),1.25rem)] pb-4">
        <Logo />
        <ButtonLink href="/app" size="sm">
          Open app
        </ButtonLink>
      </header>
      <main className="relative mx-auto max-w-3xl px-5 pt-12 pb-24">
        <Eyebrow>Privacy</Eyebrow>
        <h1 className="mt-3 font-display text-5xl leading-tight sm:text-6xl">
          Private by <em className="text-accent">default.</em>
        </h1>
        <p className="mt-5 max-w-xl text-[17px] leading-relaxed text-muted">
          Conversations are personal. Here’s exactly what happens to what you share.
        </p>
        <div className="mt-14 divide-y divide-line border-y border-line">
          {SECTIONS.map((s) => (
            <section key={s.title} className="grid gap-3 py-8 sm:grid-cols-[1fr_1.6fr] sm:gap-10">
              <h2 className="text-base font-medium">{s.title}</h2>
              <div className="space-y-3 text-[15px] leading-relaxed text-muted">
                {s.body.map((p) => (
                  <p key={p}>{p}</p>
                ))}
              </div>
            </section>
          ))}
        </div>
      </main>
    </div>
  );
}
