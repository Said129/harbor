import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import ts from "typescript";

const reference = "0834340cec5531650bfe78cd628628702e636987";
const path = "src/lib/music/parametric-eq.ts";
const input = execFileSync("git", ["show", reference + ":" + path]);
const compiled = ts.transpileModule(input.toString("utf8"), {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
}).outputText;
const source = [
  "globalThis.harborMusicParametricEQ = (() => { const exports = {};",
  compiled,
  "return raw => {",
  "const request = JSON.parse(raw); let result;",
  "if (request.operation === 'import') result = exports.importPeq(request.text);",
  "else if (request.operation === 'export') {",
  "const settings = request.settings;",
  "const filters = exports.normalizePeq(settings.peqFilters);",
  "const strength = exports.clampNumber(settings.eqStrength, 0, 1, 1);",
  "const headroom = settings.autoHeadroom ? exports.peqHeadroom(filters, strength) : 0;",
  "result = exports.exportPeq(filters.map(f => ({ ...f, gain: f.gain * strength, enabled: f.enabled && strength > 0 })), settings.preampDb - headroom);",
  "} else if (request.operation === 'response') {",
  "const rate = request.settings.sampleRate || 48000;",
  "const curve = settings => Array.from({length: 361}, (_, i) => settings.eqEnabled && !settings.dspBypass && settings.eqMode === 'parametric' ? exports.peqResponse(exports.normalizePeq(settings.peqFilters), 20 * 1000 ** (i / 360), rate, settings.eqStrength) : 0);",
  "result = { draft: curve(request.settings), applied: curve(request.applied), headroom: request.settings.autoHeadroom ? exports.peqHeadroom(exports.normalizePeq(request.settings.peqFilters), request.settings.eqStrength) : 0 };",
  "} else throw Error('invalid-correction-operation');",
  "return JSON.stringify(result);",
  "}; })();",
].join("\n");
writeFileSync(
  "ios/Harbor/MusicParametricEQAssets.json",
  JSON.stringify(
    {
      schema: 1,
      reference,
      inputs: { [path]: createHash("sha256").update(input).digest("hex") },
      program: { sha256: createHash("sha256").update(source).digest("hex"), source },
    },
    null,
    2,
  ) + "\n",
);
console.log(createHash("sha256").update(source).digest("hex"));
