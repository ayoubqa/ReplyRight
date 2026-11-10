import Link from "next/link";

/**
 * This deployment is the API for the ReplyRight iOS app. The product lives in
 * the native app; this page only points people the right way.
 */
export default function Home() {
  return (
    <main>
      <p className="eyebrow">ReplyRight for iPhone</p>
      <h1>
        Say it better. <em>Be yourself.</em>
      </h1>
      <p className="lede">
        ReplyRight is a dating communication companion for iPhone. It helps you find words that sound like you, right
        when you need them.
      </p>
      <p>This address serves the app. There is nothing to sign in to here.</p>
      <nav className="nav">
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
        <Link href="/support">Support</Link>
      </nav>
    </main>
  );
}
