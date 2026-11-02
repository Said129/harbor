import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import vm from "node:vm";
import ts from "typescript";

const reference = "0834340cec5531650bfe78cd628628702e636987";
const path = "src/lib/music/eq-presets.ts";
const source = execFileSync("git", ["show", `${reference}:${path}`]);
const exports = {};
vm.runInNewContext(
  ts.transpileModule(source.toString("utf8"), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  }).outputText,
  { exports },
  { timeout: 1000 },
);
const frequencies = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
writeFileSync(
  "ios/Harbor/MusicEQPresets.json",
  JSON.stringify(
    {
      reference,
      sha256: createHash("sha256").update(source).digest("hex"),
      frequencies,
      presets: exports.MUSIC_EQ_PRESETS.map((preset) => ({
        ...preset,
        filters: exports.peqPresetFilters(preset, frequencies),
      })),
    },
    null,
    2,
  ) + "\n",
);
