import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

const index = process.argv.indexOf("--reference");
assert(index > 0 && process.argv[index + 1]);
const reference = path.resolve(process.argv[index + 1]);
const file = "src/lib/anime-customization.ts";
const bytes = await readFile(path.join(reference, file));
const digest = createHash("sha256").update(bytes).digest("hex");
assert.equal(digest, "6d285ab82a36e2b1fee3763dd07652f6ef54cd44f5353b1fe554eb826ab7bd18");
const exports = {};
const context = vm.createContext({ exports });
const transpiled = ts.transpileModule(bytes.toString("utf8"), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
}).outputText;
vm.runInContext(transpiled, context, { timeout: 1000 });
const rows = [
  { key: "continueWatching", name: "Continue Watching" },
  { key: "airing", name: "Airing Now" },
  { key: "upcoming", name: "Upcoming Season" },
];
const cases = [
  { custom: { order: [], hidden: [], renamed: {} } },
  {
    custom: {
      order: ["upcoming", "future-row", "continueWatching"],
      hidden: ["airing"],
      renamed: { continueWatching: "Mi continuidad" },
    },
  },
  {
    custom: { order: [], hidden: [], renamed: {} },
    action: { type: "move", key: "continueWatching", delta: 1 },
  },
  {
    custom: { order: [], hidden: [], renamed: {} },
    action: { type: "hide", key: "continueWatching" },
  },
  {
    custom: { order: [], hidden: [], renamed: { continueWatching: "Old name" } },
    action: { type: "rename", key: "continueWatching", name: "" },
  },
  {
    custom: { order: [], hidden: [], renamed: {} },
    action: { type: "rename", key: "continueWatching", name: "  Acabar anime  " },
  },
];
for (const entry of cases) {
  let next = entry.custom;
  const action = entry.action;
  if (action?.type === "move") next = exports.animeMoveRow(next, rows, action.key, action.delta);
  if (action?.type === "hide") next = exports.animeToggleHidden(next, action.key);
  if (action?.type === "rename") next = exports.animeRenameRow(next, action.key, action.name);
  entry.expected = {
    visible: exports.applyAnimeRowCustomization(rows, next),
    editing: exports.applyAnimeRowCustomization(rows, next, true),
    order: exports.animeEffectiveOrder(rows, next),
  };
}
const fixture = JSON.stringify({ input_sha256: digest, rows, cases }, null, 2) + "\n";
await writeFile("ios/HarborTests/Fixtures/anime-continuation-reference.json", fixture);
await writeFile(
  "docs/ios/anime-continuation-sources.json",
  JSON.stringify(
    {
      reference: "0.9.132 (Beta)",
      inputs: { [file]: digest },
      fixture_canonical_sha256: createHash("sha256")
        .update(JSON.stringify(JSON.parse(fixture)))
        .digest("hex"),
      original_customization_functions_executed: true,
      native_continue_row: "continueWatching",
      new_native_cases: 4,
      unexecuted_page_layout_cases_retained: 16,
      prior_page_layout_run: 40140794453,
      prior_page_layout_actual_executions: 0,
      new_ui_routes: 2,
      fresh_ui_preparations: 2,
      expected_total_executions: 24,
      expected_original_images: 12,
      full_desktop_parity_complete: false,
      ipa_created: false,
    },
    null,
    2,
  ) + "\n",
);
console.log(JSON.stringify({ original_vectors: cases.length, reference_sha256: digest }));
