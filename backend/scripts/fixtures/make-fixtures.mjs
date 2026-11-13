#!/usr/bin/env node
/**
 * Builds the screenshots `scripts/verify.mjs` uploads.
 *
 * They are drawings of a made-up chat between two fictional adults, in a
 * generic messaging style (no real app's look), rendered in Chromium and saved
 * as JPEG the way the iOS app sends screenshots.
 *
 *   chat-1.jpg        the start of a conversation
 *   chat-2.jpg        what comes next, for the two-screenshot check
 *   chat-blurred.jpg  chat-1 blurred until nothing can be read
 *   not-a-chat.jpg    a drawing of a landscape, no conversation in it
 *
 * Needs Playwright with Chromium (`npx playwright install chromium`) and sharp.
 *   node scripts/fixtures/make-fixtures.mjs
 */
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const here = dirname(fileURLToPath(import.meta.url));

const CHAT_1 = [
  ["them", "ok be honest, pineapple on pizza?"],
  ["me", "depends who's asking"],
  ["them", "someone deciding whether we can be friends"],
  ["me", "then yes. obviously yes"],
];
const CHAT_2 = [
  ["them", "good answer"],
  ["them", "are we still on for friday?"],
  ["me", "unless you found someone better"],
  ["them", "kidding. 8pm at the ramen place?"],
];

function chatPage(lines, name) {
  const bubbles = lines
    .map(
      ([who, text]) =>
        `<div class="row ${who}"><div class="bubble">${text.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</div></div>`,
    )
    .join("");
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    * { box-sizing: border-box; margin: 0; }
    body { width: 390px; height: 844px; font: 17px/1.3 -apple-system, "Helvetica Neue", Arial, sans-serif; background: #f2f2f4; color: #111; }
    .status { height: 47px; display: flex; justify-content: space-between; align-items: flex-end; padding: 0 28px 6px; font-weight: 600; font-size: 15px; }
    .header { height: 64px; border-bottom: 1px solid #ddd; display: flex; flex-direction: column; align-items: center; justify-content: center; background: #fafafa; }
    .avatar { width: 34px; height: 34px; border-radius: 50%; background: #c9c3d6; }
    .name { font-size: 12px; margin-top: 3px; color: #333; }
    .thread { padding: 18px 14px; display: flex; flex-direction: column; gap: 8px; }
    .row { display: flex; }
    .row.me { justify-content: flex-end; }
    .bubble { max-width: 74%; padding: 9px 14px; border-radius: 19px; }
    .them .bubble { background: #e5e5ea; }
    .me .bubble { background: #2f7cf6; color: #fff; }
    .composer { position: absolute; left: 0; right: 0; bottom: 0; height: 84px; border-top: 1px solid #ddd; background: #fafafa; padding: 10px 14px; }
    .field { height: 36px; border: 1px solid #ccc; border-radius: 18px; background: #fff; color: #999; padding: 8px 14px; font-size: 16px; }
  </style></head><body>
    <div class="status"><span>9:41</span><span>100%</span></div>
    <div class="header"><div class="avatar"></div><div class="name">${name}</div></div>
    <div class="thread">${bubbles}</div>
    <div class="composer"><div class="field">Message</div></div>
  </body></html>`;
}

const LANDSCAPE = `<!doctype html><html><body style="margin:0">
  <svg xmlns="http://www.w3.org/2000/svg" width="390" height="844" viewBox="0 0 390 844">
    <defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6b38a"/><stop offset="1" stop-color="#f7e1b5"/></linearGradient></defs>
    <rect width="390" height="844" fill="url(#sky)"/>
    <circle cx="270" cy="300" r="70" fill="#fff3d6"/>
    <path d="M0 560 Q 100 470 200 540 T 390 520 V 844 H 0 Z" fill="#7f9c74"/>
    <path d="M0 640 Q 120 580 240 650 T 390 630 V 844 H 0 Z" fill="#5d7c56"/>
    <path d="M0 740 Q 150 700 390 760 V 844 H 0 Z" fill="#3f5a3b"/>
  </svg></body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
async function shoot(html) {
  await page.setContent(html);
  return page.screenshot({ type: "png" });
}
const jpeg = (png, sigma) => {
  const image = sharp(png);
  return (sigma ? image.blur(sigma) : image).jpeg({ quality: 85 }).toBuffer();
};

const chat1 = await shoot(chatPage(CHAT_1, "Sam"));
const chat2 = await shoot(chatPage(CHAT_2, "Sam"));
const landscape = await shoot(LANDSCAPE);
await browser.close();

await sharp(await jpeg(chat1)).toFile(join(here, "chat-1.jpg"));
await sharp(await jpeg(chat2)).toFile(join(here, "chat-2.jpg"));
await sharp(await jpeg(chat1, 28)).toFile(join(here, "chat-blurred.jpg"));
await sharp(await jpeg(landscape)).toFile(join(here, "not-a-chat.jpg"));
console.log("Wrote chat-1.jpg, chat-2.jpg, chat-blurred.jpg and not-a-chat.jpg in", here);
