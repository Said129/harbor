import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const args = process.argv.slice(2),
  index = args.indexOf("--reference");
assert(index >= 0 && args[index + 1]);
const name = "src/lib/streams/plugins/runtime.ts";
const hash = "9b41fb8a2c012b136efd9bef927f6e9626f4f8f2371b80999a087c71dae7bdf2";
const source = (await readFile(path.join(path.resolve(args[index + 1]), name), "utf8")).replaceAll(
  "\r\n",
  "\n",
);
const digest = (value) => createHash("sha256").update(value).digest("hex");
assert.equal(digest(source), hash);
const start = source.indexOf("function normalizeField(");
const end = source.indexOf("\nexport async function streamPluginSettingsFields(", start);
assert(start > 0 && end > start);
const compiled = ts.transpileModule(source.slice(start, end), {
  fileName: name,
  compilerOptions: { target: ts.ScriptTarget.ES2020 },
  reportDiagnostics: true,
});
assert.equal(compiled.diagnostics?.length ?? 0, 0);
const program =
  compiled.outputText +
  `
globalThis.harborNormalizePluginFields = function (json) {
  const raw = JSON.parse(json);
  const list = Array.isArray(raw) ? raw : raw && typeof raw === "object" && Array.isArray(raw.fields) ? raw.fields : [];
  return JSON.stringify(list.map(normalizeField).filter(function (field) { return !!field; }));
};
`;
const inputs = [
  null,
  {},
  [],
  { fields: "invalid" },
  [
    { type: "header", label: "Account" },
    { type: "info", label: "Owned information", description: "ignored" },
  ],
  [
    { type: "header", label: "" },
    { type: "info", label: 2 },
    { type: "unknown", key: "x" },
    null,
    "bad",
    [],
  ],
  [
    {
      type: "text",
      key: "token",
      label: "Token",
      isPassword: true,
      placeholder: "Owned placeholder",
      description: "Owned description",
      defaultValue: "",
    },
  ],
  [
    { type: "text", key: "secret", secret: true },
    { type: "text", key: "plain", defaultValue: false },
    { type: "text", key: "", label: "Missing key" },
  ],
  {
    fields: [
      { type: "toggle", key: "one", defaultValue: false },
      { type: "boolean", key: "two", defaultValue: true },
      { type: "checkbox", key: "three", defaultValue: 1 },
    ],
  },
  [
    {
      type: "select",
      key: "quality",
      options: [
        { value: 1080, label: "Full HD" },
        { value: 720 },
        { value: 0 },
        { value: false },
        { value: null },
        { value: "" },
        "bad",
      ],
      defaultValue: 720,
    },
  ],
  [
    {
      type: "select",
      key: "coercion",
      options: [
        { value: 1e-7 },
        { value: 1e20 },
        { value: [1, null, "x"] },
        { value: {} },
        { value: [] },
      ],
      defaultValue: false,
    },
  ],
  [
    { type: "select", key: "empty", options: [] },
    { type: "select", key: "missing" },
  ],
  [{ type: "text", key: " white space ", label: " ", defaultValue: "العربية 日本語" }],
  [{ type: "select", key: "invalid-coercion", options: [{ value: { toString: 7 } }] }],
];
const context = vm.createContext({});
vm.runInContext(program, context, { timeout: 1000 });
const cases = inputs.map((input) => {
  context.rawJSON = JSON.stringify(input);
  try {
    return {
      input,
      expected: JSON.parse(
        vm.runInContext("harborNormalizePluginFields(rawJSON)", context, { timeout: 1000 }),
      ),
    };
  } catch {
    return { input, error: "plugin-settings-normalization" };
  }
});
const reference = "0834340cec5531650bfe78cd628628702e636987";
const asset = {
  schema: 1,
  reference,
  inputs: { [name]: hash },
  program: { source: program, sha256: digest(program) },
};
const fixture = { schema: 1, reference, inputs: { [name]: hash }, cases };
for (const [file, value] of [
  ["ios/Harbor/PluginSettingsNormalizer.json", asset],
  ["ios/HarborTests/Fixtures/plugin-settings-reference.json", fixture],
]) {
  const target = path.join(root, file);
  if (args.includes("--check")) assert.deepEqual(JSON.parse(await readFile(target, "utf8")), value);
  else await writeFile(target, JSON.stringify(value, null, 2) + "\n");
}
process.stdout.write(
  JSON.stringify({ cases: cases.length, referenceExecuted: true, nativeExecuted: false }) + "\n",
);
