import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const args = process.argv.slice(2);
const index = args.indexOf("--reference");
assert(index >= 0 && args[index + 1], "Provide the pinned Desktop reference directory");
const reference = path.resolve(args[index + 1]);
const check = args.includes("--check");
const commit = "0834340cec5531650bfe78cd628628702e636987";
const inputs = {
  "src/lib/manga/plugins/sandbox.ts":
    "535a16cb2cb923239ddc2f63faacb52b49e7a1350c23bac9a398eccb567fb899",
  "src/lib/manga/plugins/host-parse.ts":
    "de46230e8e9eef3bc25418fee98d27949ef00bed82901529a8cdc5fa31eb4aff",
  "src/lib/streams/plugins/provider-compat/prelude.ts":
    "ed888bd213f0d59fdb3420d28bf20c7b59c37853b99e3447b7e27d1d9c7b9d86",
  "src/lib/streams/plugins/provider-compat/cheerio.ts":
    "7c3a2007bc29f0a1b8fac1857d5e9062e47a046a7836323467c3ca3ede6308a4",
  "src/lib/manga/sources/mangayomi/prelude/dom.ts":
    "392f0829cd4f8f2eef9fd09b8603cfd658eca60af4dcf2d794a6bc20cb4be739",
  "src/lib/manga/sources/mangayomi/prelude/crypto.ts":
    "8a59231b823e456abc432f5510e1d32f7f3eb116bc218c207231cb03f372618b",
};
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const compiled = new Map();
assert.equal(
  JSON.parse(await readFile(path.join(reference, "package.json"), "utf8")).version,
  "0.9.132",
);
for (const [name, hash] of Object.entries(inputs)) {
  const source = (await readFile(path.join(reference, name), "utf8")).replaceAll("\r\n", "\n");
  assert.equal(sha256(source), hash, `Reference input changed: ${name}`);
  const result = ts.transpileModule(source, {
    fileName: name,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    reportDiagnostics: true,
  });
  assert.equal(result.diagnostics?.length ?? 0, 0, `Transpilation diagnostics: ${name}`);
  compiled.set(name, result.outputText.replaceAll("\r\n", "\n"));
}

const exported = {};
vm.runInNewContext(
  compiled.get("src/lib/manga/plugins/sandbox.ts"),
  { exports: exported },
  { timeout: 1000 },
);
assert.equal(typeof exported.SANDBOX_SOURCE, "string");
// JavaScriptCore's Error.stack omits the message that Chromium includes.
// Adapt only initialization diagnostics, leaving execution and host policies intact.
const initializationError = "String(err && err.stack ? err.stack : err)";
assert.equal(exported.SANDBOX_SOURCE.split(initializationError).length, 2);
const sandbox = exported.SANDBOX_SOURCE.replace(
  initializationError,
  'String(err) + (err && err.stack ? "\\n" + String(err.stack) : "")',
);
const parser = `(function () { const exports = {};\n${compiled.get("src/lib/manga/plugins/host-parse.ts")}\nreturn exports.serializeHtml; })()`;
const modules = [
  ["@/lib/manga/sources/mangayomi/prelude/dom", "src/lib/manga/sources/mangayomi/prelude/dom.ts"],
  [
    "@/lib/manga/sources/mangayomi/prelude/crypto",
    "src/lib/manga/sources/mangayomi/prelude/crypto.ts",
  ],
  ["./cheerio", "src/lib/streams/plugins/provider-compat/cheerio.ts"],
  ["entry", "src/lib/streams/plugins/provider-compat/prelude.ts"],
];
const factories = modules
  .map(
    ([id, name]) =>
      `${JSON.stringify(id)}: function (exports, require) {\n${compiled.get(name)}\n}`,
  )
  .join(",\n");
const composer = `(function () {\nconst factories = {${factories}}; const cache = Object.create(null);\nfunction require(id) { if (cache[id]) return cache[id]; if (!Object.hasOwn(factories, id)) throw new Error("Unknown bundled module"); const exports = {}; cache[id] = exports; factories[id](exports, require); return exports; }\nconst entry = require("entry"); return { harbor: entry.composeHarborSource, provider: entry.composeProviderSource }; })()`;
const programs = Object.fromEntries(
  Object.entries({ sandbox, parser, composer }).map(([name, source]) => {
    const script = new vm.Script(name === "sandbox" ? source : `void ${source}`);
    assert(script);
    return [name, { source, sha256: sha256(source) }];
  }),
);
const asset = {
  schema: 1,
  reference: commit,
  desktopVersion: "0.9.132",
  compiler: `typescript@${ts.version}`,
  inputHashConvention: "UTF-8 with CRLF normalized to LF",
  inputs,
  adaptations: ["Preserve initialization error message with JavaScriptCore stacks"],
  programs,
};
const target = path.join(root, "ios/Harbor/PluginRuntimeAssets.json");
if (check)
  assert.deepEqual(
    JSON.parse(await readFile(target, "utf8")),
    asset,
    "Bundled runtime differs from the pinned reference",
  );
else await writeFile(target, JSON.stringify(asset, null, 2) + "\n", "utf8");
console.log(
  `${check ? "Verified" : "Generated"} six pinned inputs and three executable runtime programs. This does not validate iOS execution or complete Plugins.`,
);
