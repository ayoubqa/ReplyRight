import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Support" };

const SUPPORT_EMAIL = process.env.NEXT_PUBLIC_SUPPORT_EMAIL ?? "support@example.com";

export default function Support() {
  return (
    <main>
      <p className="eyebrow">Support</p>
      <h1>
        We&apos;re here <em>to help.</em>
      </h1>

      <h2>Turning on the keyboard</h2>
      <p>
        Open Settings, then General, Keyboard, Keyboards, Add New Keyboard, and choose ReplyRight. To use AI features
        from the keyboard, tap ReplyRight in that list and turn on Allow Full Access. Typing works without it.
      </p>

      <h2>Managing your subscription</h2>
      <p>
        Open Settings, tap your name, then Subscriptions. You can also restore purchases from the app under You,
        Subscription.
      </p>

      <h2>Deleting your data</h2>
      <p>
        Everything you save lives on your iPhone. Open the app, go to You, Privacy Center, and choose what to delete,
        or erase everything at once.
      </p>

      <h2>Contact</h2>
      <p>
        Email <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
      </p>
      <nav className="nav">
        <Link href="/">Home</Link>
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
      </nav>
    </main>
  );
}
