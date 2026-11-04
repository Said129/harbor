import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import vm from "node:vm";
import { deflateSync } from "node:zlib";
import ts from "typescript";

const reference = "0834340cec5531650bfe78cd628628702e636987";
const input = execFileSync("git", ["show", reference + ":src/lib/music/appearance.ts"]);
const asset = JSON.parse(readFileSync("ios/Harbor/MusicArtworkAssets.json", "utf8"));
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
assert.equal(asset.reference, reference);
assert.equal(asset.inputs["src/lib/music/appearance.ts"], sha(input));
assert.equal(asset.program.sha256, sha(asset.program.source));
// Evaluate the complete, unchanged Desktop module independently of the selected
// function bundle. Only unused platform imports/top-level preference wiring are
// stubbed; no expected colour result comes from the adapted program.
const original = {
  exports: {},
  require: (name) => {
    if (name === "./preferences") return { readMusicPreference: () => null };
    if (name === "./window-sync") return { subscribeWindowState: () => {} };
    if (name === "./miku-models") return { normalizeMikuModel: () => "miku" };
    if (name === "./gif-clock") return { normalizeGifTiming: () => "auto" };
    if (name === "react" || name === "@tauri-apps/api/core") return {};
    throw Error("Unexpected original artwork dependency: " + name);
  },
};
vm.runInNewContext(
  ts.transpileModule(input.toString("utf8"), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  }).outputText,
  original,
  { timeout: 1000 },
);
const adapted = {};
vm.runInNewContext(asset.program.source, adapted, { timeout: 1000 });
const rgb = (text) => text.match(/\d+/g).map(Number);
const result = (pixels) => {
  const color = original.exports.musicArtworkColor(pixels);
  return {
    dominant: color ? { rgb: rgb(color.color), darkInk: color.ink === "#111111" } : null,
    palette: Array.from(original.exports.musicArtworkPalette(pixels), rgb),
  };
};
const cases = [
  ["empty", []],
  ["transparent", [220, 20, 30, 127]],
  ["alpha-boundary", [220, 20, 30, 128]],
  ["black-white", [0, 0, 0, 255, 255, 255, 255, 255]],
  ["gray", [128, 128, 128, 255]],
  ["bright-yellow", [240, 210, 30, 255]],
  ["stable-tie-red-first", [220, 32, 32, 255, 32, 32, 220, 255]],
  ["stable-tie-blue-first", [32, 32, 220, 255, 220, 32, 32, 255]],
  ["near-bin-edges", [23, 24, 31, 255, 24, 31, 32, 255, 31, 32, 47, 255, 32, 47, 48, 255]],
];
let seed = 0x132;
for (let index = 0; index < 64; index++) {
  const pixels = Array.from({ length: (index < 8 ? index + 1 : 576) * 4 }, () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed >>> 24;
  });
  cases.push(["generated-" + index, pixels]);
}
const vectors = cases.map(([name, pixels]) => {
  const expected = JSON.parse(JSON.stringify(result(pixels)));
  assert.deepEqual(JSON.parse(adapted.harborMusicArtwork(JSON.stringify(pixels))), expected, name);
  return { name, pixels, expected };
});
for (const invalid of [[1], [-1, 0, 0, 255], [0.5, 0, 0, 255], Array(2308).fill(0), null]) {
  assert.throws(() => adapted.harborMusicArtwork(JSON.stringify(invalid)));
}
// Keep edge cases and two full 24x24 generated vectors for native JSCore.
const native = [...vectors.slice(0, 17), ...vectors.slice(17, 19)];
writeFileSync(
  "ios/HarborTests/Fixtures/music-artwork-reference.json",
  JSON.stringify(
    {
      reference,
      inputSHA256: sha(input),
      programSHA256: asset.program.sha256,
      referenceEvaluation: "Complete pinned Desktop module, independently transpiled",
      cases: native,
    },
    null,
    2,
  ) + "\n",
);
// An owned lossless image with an intentional dominant-colour tie. Its top
// row must remain first after ImageIO/CoreGraphics decoding, like canvas.
const crc32 = (bytes) => {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
};
const chunk = (name, data) => {
  const body = Buffer.concat([Buffer.from(name), data]);
  const length = Buffer.alloc(4),
    crc = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
};
const header = Buffer.alloc(13);
header.writeUInt32BE(24, 0);
header.writeUInt32BE(24, 4);
header[8] = 8;
header[9] = 6;
const rows = [];
for (let row = 0; row < 24; row++) {
  rows.push(
    Buffer.from([0]),
    Buffer.from(
      Array(24)
        .fill(row < 12 ? [220, 32, 32, 255] : [32, 32, 220, 255])
        .flat(),
    ),
  );
}
const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk("IHDR", header),
  chunk("IDAT", deflateSync(Buffer.concat(rows))),
  chunk("IEND", Buffer.alloc(0)),
]);
writeFileSync("ios/HarborTests/Fixtures/owned-music-artwork.png", png);
console.log(
  JSON.stringify({
    comparedWithOriginal: vectors.length,
    rejectedInvalidInputs: 5,
    nativeVectors: native.length,
  }),
);
