#!/usr/bin/env node
/**
 * Renders the brand SVGs to PNG and fills the Xcode asset catalog.
 * Needs Playwright with Chromium:  node brand/render.js
 */
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const here = __dirname;
const assets = path.join(here, "..", "ios", "ReplyRight", "Resources", "Assets.xcassets");

async function png(page, file, width, height, output, transparent) {
  const svg = fs.readFileSync(path.join(here, file), "utf8");
  await page.setViewportSize({ width, height });
  await page.setContent(
    `<html><body style="margin:0;background:transparent">${svg.replace("<svg ", `<svg style="display:block;width:${width}px;height:${height}px" `)}</body></html>`,
  );
  fs.mkdirSync(path.dirname(output), { recursive: true });
  await page.screenshot({ path: output, omitBackground: transparent });
}

function write(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof content === "string" ? content : JSON.stringify(content, null, 2) + "\n");
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });

  // App icon: any, dark and tinted appearances (iOS 18). Opaque, square, 1024.
  const icon = path.join(assets, "AppIcon.appiconset");
  await png(page, "app-icon.svg", 1024, 1024, path.join(icon, "AppIcon-1024.png"), false);
  await png(page, "app-icon-dark.svg", 1024, 1024, path.join(icon, "AppIcon-1024-dark.png"), false);
  await png(page, "app-icon-tinted.svg", 1024, 1024, path.join(icon, "AppIcon-1024-tinted.png"), false);
  write(path.join(icon, "Contents.json"), {
    images: [
      { filename: "AppIcon-1024.png", idiom: "universal", platform: "ios", size: "1024x1024" },
      {
        appearances: [{ appearance: "luminosity", value: "dark" }],
        filename: "AppIcon-1024-dark.png",
        idiom: "universal",
        platform: "ios",
        size: "1024x1024",
      },
      {
        appearances: [{ appearance: "luminosity", value: "tinted" }],
        filename: "AppIcon-1024-tinted.png",
        idiom: "universal",
        platform: "ios",
        size: "1024x1024",
      },
    ],
    info: { author: "xcode", version: 1 },
  });

  // Symbol and logo as vectors, with a light and a dark version each.
  for (const [name, light, dark] of [
    ["BrandSymbol", "symbol-light.svg", "symbol.svg"],
    ["BrandLogo", "logo-light.svg", "logo.svg"],
  ]) {
    const dir = path.join(assets, `${name}.imageset`);
    fs.mkdirSync(dir, { recursive: true });
    fs.copyFileSync(path.join(here, light), path.join(dir, `${name}-light.svg`));
    fs.copyFileSync(path.join(here, dark), path.join(dir, `${name}-dark.svg`));
    write(path.join(dir, "Contents.json"), {
      images: [
        { filename: `${name}-light.svg`, idiom: "universal" },
        { appearances: [{ appearance: "luminosity", value: "dark" }], filename: `${name}-dark.svg`, idiom: "universal" },
      ],
      info: { author: "xcode", version: 1 },
      properties: { "preserves-vector-representation": true },
    });
  }

  // The mark shown while the app launches.
  const launch = path.join(assets, "LaunchMark.imageset");
  for (const scale of [1, 2, 3]) {
    await png(page, "launch-mark.svg", 120 * scale, 120 * scale, path.join(launch, `LaunchMark@${scale}x.png`), true);
  }
  write(path.join(launch, "Contents.json"), {
    images: [1, 2, 3].map((scale) => ({ filename: `LaunchMark@${scale}x.png`, idiom: "universal", scale: `${scale}x` })),
    info: { author: "xcode", version: 1 },
  });

  // Previews for people reading the repository.
  await png(page, "app-icon.svg", 512, 512, path.join(here, "png", "app-icon.png"), false);
  await png(page, "app-icon-dark.svg", 512, 512, path.join(here, "png", "app-icon-dark.png"), false);
  await png(page, "app-icon-tinted.svg", 512, 512, path.join(here, "png", "app-icon-tinted.png"), false);
  await png(page, "symbol.svg", 512, 512, path.join(here, "png", "symbol.png"), true);
  await png(page, "symbol-light.svg", 512, 512, path.join(here, "png", "symbol-light.png"), true);

  await browser.close();
  console.log("Rendered brand assets into", assets);
})();
