import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Terms of Use" };

export default function Terms() {
  return (
    <main>
      <p className="eyebrow">Terms of Use</p>
      <h1>
        The short, <em>honest</em> version.
      </h1>
      <p className="note">
        <strong>Draft for review.</strong> Have these terms reviewed by a lawyer and add your company details before
        publishing. If you prefer, you can use Apple&apos;s standard licence agreement instead.
      </p>

      <h2>What ReplyRight is</h2>
      <p>
        ReplyRight suggests wording for your own messages. Suggestions are options. You decide what to send, and you
        are responsible for what you send. ReplyRight never sends messages for you.
      </p>

      <h2>What it is not</h2>
      <p>
        ReplyRight cannot know what another person thinks or feels, and it makes no promises about how anyone will
        respond. It is not a substitute for professional advice.
      </p>

      <h2>Using it respectfully</h2>
      <p>
        You must be 18 or older. Do not use ReplyRight to harass, deceive, pressure or manipulate anyone, or to
        continue contact with someone who has asked you to stop. Only share conversations you are part of.
      </p>

      <h2>Subscriptions</h2>
      <p>
        ReplyRight Pro is an auto-renewing subscription billed through your Apple Account. It renews unless cancelled
        at least 24 hours before the end of the current period. You can manage or cancel it in your App Store account
        settings. Prices are shown in the app before you buy.
      </p>

      <h2>Changes</h2>
      <p>We may update these terms as the product changes. Continued use means you accept the current version.</p>

      <nav className="nav">
        <Link href="/">Home</Link>
        <Link href="/privacy">Privacy</Link>
        <Link href="/support">Support</Link>
      </nav>
    </main>
  );
}
