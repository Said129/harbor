import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import ts from "typescript";

const reference = "0834340cec5531650bfe78cd628628702e636987";
const path = "src/lib/music/appearance.ts";
const input = execFileSync("git", ["show", reference + ":" + path]);
const file = ts.createSourceFile(path, input.toString("utf8"), ts.ScriptTarget.Latest, true);
const wanted = new Set(["musicArtworkColor", "hueOf", "lumaOf", "vividOf", "musicArtworkPalette"]);
const selected = file.statements.filter(
  (item) => ts.isFunctionDeclaration(item) && wanted.has(item.name?.text),
);
if (selected.length !== wanted.size) throw Error("Review the pinned artwork functions");
const compiled = ts.transpileModule(selected.map((item) => item.getText(file)).join("\n"), {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
}).outputText;
const source = [
  "globalThis.harborMusicArtwork = (() => { const exports = {};",
  compiled,
  "return raw => {",
  "const pixels = JSON.parse(raw);",
  "if (!Array.isArray(pixels) || pixels.length > 2304 || pixels.length % 4 || !pixels.every(n => Number.isInteger(n) && n >= 0 && n <= 255)) throw Error('invalid-artwork-pixels');",
  "const rgb = value => { const m = /^rgb\\((\\d+) (\\d+) (\\d+)\\)$/.exec(value); if (!m) throw Error('invalid-artwork-color'); return m.slice(1).map(Number); };",
  "const dominant = exports.musicArtworkColor(pixels);",
  "return JSON.stringify({ dominant: dominant ? { rgb: rgb(dominant.color), darkInk: dominant.ink === '#111111' } : null, palette: exports.musicArtworkPalette(pixels).map(rgb) });",
  "}; })();",
].join("\n");
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
writeFileSync(
  "ios/Harbor/MusicArtworkAssets.json",
  JSON.stringify(
    {
      schema: 1,
      reference,
      inputs: { [path]: digest(input) },
      functions: [...wanted],
      program: { sha256: digest(source), source },
    },
    null,
    2,
  ) + "\n",
);
console.log(JSON.stringify({ inputSHA256: digest(input), programSHA256: digest(source) }));
