import type { Metadata, Viewport } from "next";
import "./site.css";

export const metadata: Metadata = {
  title: { default: "ReplyRight", template: "%s · ReplyRight" },
  description: "ReplyRight for iPhone. Say it better. Be yourself.",
};

export const viewport: Viewport = { themeColor: "#0e0b14", width: "device-width", initialScale: 1 };

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
