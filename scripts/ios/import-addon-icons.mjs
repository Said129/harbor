// Rasterize the original SVG masks, including their embedded PNG data, for iOS.
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const records = {};
for (const name of [
  "streams",
  "catalogs",
  "subtitles",
  "anime",
  "sports",
  "livetv",
  "tools",
  "adult",
]) {
  const relative = `src/assets/category/${name}.svg`;
  const source = readFileSync(resolve(root, relative));
  const png = new Resvg(source, { fitTo: { mode: "width", value: 256 } }).render().asPng();
  const target = resolve(root, `ios/Harbor/Assets.xcassets/category-${name}.imageset`);
  mkdirSync(target, { recursive: true });
  writeFileSync(resolve(target, "icon.png"), png);
  writeFileSync(
    resolve(target, "Contents.json"),
    JSON.stringify(
      {
        images: [{ idiom: "universal", filename: "icon.png" }],
        info: { author: "xcode", version: 1 },
        properties: { "template-rendering-intent": "template" },
      },
      null,
      2,
    ) + "\n",
  );
  records[name] = {
    source: relative,
    sourceSha256: createHash("sha256").update(source).digest("hex"),
    pngSha256: createHash("sha256").update(png).digest("hex"),
    width: 256,
  };
}
writeFileSync(
  resolve(root, "docs/ios/addon-category-icon-provenance.json"),
  JSON.stringify(
    {
      renderer: "@resvg/resvg-js",
      reference: "src/views/addons/category-grid.tsx",
      notes:
        "Original Harbor category SVG geometry, embedded images and masks rasterized without replacements. Tint is supplied by the native catalog. This is the public source checkpoint; supplied Desktop 0.9.130 screenshots remain the visual reference.",
      icons: records,
    },
    null,
    2,
  ) + "\n",
);
process.stdout.write(`Imported ${Object.keys(records).length} original addon category icons\n`);
