import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

const argument = process.argv.indexOf("--reference");
assert(argument >= 0 && process.argv[argument + 1]);
const file = "src/views/ebook/harbor-reader.tsx";
const original = (await readFile(path.join(process.argv[argument + 1], file), "utf8")).replaceAll(
  "\r\n",
  "\n",
);
const sha256 = createHash("sha256").update(original).digest("hex");
assert.equal(sha256, "f7e467b133daf92e7b8b882a070cf2a3254592ad5d09cbc29a34b6fc3a81679f");
const tree = ts.createSourceFile(file, original, ts.ScriptTarget.Latest, true);
const variables = new Map();
function visit(node) {
  if (ts.isVariableDeclaration(node)) variables.set(node.name.getText(tree), node);
  ts.forEachChild(node, visit);
}
visit(tree);
const names = ["narrationVoices", "VOICE_SAMPLE_TEXT", "VOICE_SAMPLE_BY_LOCALE"];
const definitions = names
  .map((name) => {
    const node = variables.get(name);
    assert(node?.initializer);
    return "const " + node.getText(tree) + ";";
  })
  .join("\n");
const source = ts.transpileModule(
  definitions +
    "\nJSON.stringify({voices:narrationVoices,samples:VOICE_SAMPLE_TEXT,locales:VOICE_SAMPLE_BY_LOCALE});",
  {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None },
  },
).outputText;
const values = JSON.parse(vm.runInNewContext(source, {}, { timeout: 1000 }));
assert.equal(values.voices.length, 20);
assert.equal(new Set(values.voices.map((voice) => voice.id)).size, 20);
assert.equal(values.voices[0].id, "en-US-AvaNeural");
assert(values.samples.es && values.locales["ar-SA"] !== values.locales["ar-EG"]);
const asset = {
  schema: 1,
  reference: "8274f05485554e531cf5654574de84108f16bdb7",
  inputs: { [file]: sha256 },
  voices: values.voices.map((voice) => ({
    id: voice.id,
    locale: voice.locale,
    gender: voice.tone.includes("Female") ? "Female" : "Male",
    name: voice.label,
  })),
  samples: values.samples,
  locales: values.locales,
};
await writeFile("ios/Harbor/EBookNarrationAssets.json", JSON.stringify(asset, null, 2) + "\n");
console.log(
  "Preserved all 20 original fallback voices and original language/locale preview samples.",
);
