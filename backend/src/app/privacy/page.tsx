import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Privacy Policy" };

export default function Privacy() {
  return (
    <main>
      <p className="eyebrow">Privacy Policy</p>
      <h1>
        Your conversations <em>stay yours.</em>
      </h1>
      <p className="lede">
        ReplyRight handles some of the most personal messages you have. This page explains, in plain language, what
        the app does with them.
      </p>
      <p className="note">
        <strong>Draft for review.</strong> This text describes how the software behaves. Have it reviewed by a lawyer
        and add your company details before publishing.
      </p>

      <h2>What you share, and when</h2>
      <p>
        Nothing leaves your iPhone until you ask for something: tapping a button to read a conversation, write
        replies, rewrite a draft or ask the coach. ReplyRight never reads your other apps, never monitors your
        messages in the background and never sends anything on your behalf.
      </p>

      <h2>Screenshots and messages</h2>
      <p>
        Screenshots are resized on your device and stripped of hidden metadata before upload. Our server holds them in
        memory for the length of one request, passes them to our AI provider to read the conversation, and discards
        them. We do not save screenshots or message text to a database, and we do not write their contents to logs.
      </p>

      <h2>The ReplyRight keyboard</h2>
      <p>
        The keyboard works for typing without Full Access. Full Access is only needed for AI features, because iOS
        requires it for any keyboard that uses the network. With Full Access on, the keyboard still sends nothing
        while you type. It sends text only when you tap a ReplyRight action, and only the draft or context involved in
        that action. It does not collect keystrokes, and its AI features switch off in password, one-time-code and
        payment fields.
      </p>

      <h2>What is stored on your iPhone</h2>
      <p>
        Your voice profile, saved replies, saved sessions and any notes about people you add (under a nickname) are
        stored on your device. You can delete any of it, or everything, from the Privacy Center in the app.
      </p>

      <h2>What our server sees</h2>
      <ul>
        <li>The content of each request you make, for the time it takes to answer it.</li>
        <li>A random install identifier created by the app, used only to count daily usage.</li>
        <li>If you subscribe, the signed App Store transaction that proves your subscription.</li>
        <li>Standard technical data such as your IP address, used for rate limiting and abuse prevention.</li>
      </ul>
      <p>We do not run analytics on the content of your conversations, and we do not sell personal data.</p>

      <h2>AI provider</h2>
      <p>
        Requests are processed by Anthropic under its commercial API terms. Content is sent only to generate your
        result.
      </p>

      <h2>Adults only</h2>
      <p>ReplyRight is for people aged 18 and over.</p>

      <h2>Contact</h2>
      <p>
        Questions or requests: see <Link href="/support">Support</Link>.
      </p>
      <nav className="nav">
        <Link href="/">Home</Link>
        <Link href="/terms">Terms</Link>
        <Link href="/support">Support</Link>
      </nav>
    </main>
  );
}
