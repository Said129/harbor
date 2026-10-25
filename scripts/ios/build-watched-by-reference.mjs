import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

const index = process.argv.indexOf("--reference");
assert(index > 0 && process.argv[index + 1]);
const reference = path.resolve(process.argv[index + 1]);
const inputs = {
  "src/lib/profile-sync/watched-by-merge.ts":
    "a4d167480e2ddb36ae8580b2ecb4ad408b374d8664dbafdfff1cc220b3dfec29",
  "src/lib/watched-by.ts": "9cf28f1322c2e54bb188be8a5b128d9d2fb2ede013f63d23529d013557a4f2d7",
};
const modules = [];
for (const [file, digest] of Object.entries(inputs)) {
  const bytes = await readFile(path.join(reference, file));
  assert.equal(createHash("sha256").update(bytes).digest("hex"), digest);
  modules.push(
    ts.transpileModule(bytes.toString("utf8"), {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
    }).outputText,
  );
}
const merge = {};
vm.runInContext(modules[0], vm.createContext({ exports: merge }), { timeout: 1000 });
const cases = [
  { local: null, incoming: ["invalid"] },
  { local: { film: "p_old", empty: "", invalid: { p: false }, odd: 7 }, incoming: null },
  {
    local: { a: { p: "one", t: 100 }, b: { p: "two", t: "invalid" } },
    incoming: { a: { p: "remote", t: 101 }, c: "legacy" },
  },
  {
    local: { a: { p: "local", t: 100 } },
    incoming: { a: { p: "tie", t: 100 }, b: { p: "negative", t: -1 } },
  },
  {
    local: Object.fromEntries(
      Array.from({ length: 301 }, (_, i) => ["media-" + i, { p: "p_" + i, t: i }]),
    ),
    incoming: { newest: { p: "new", t: 900 } },
  },
];
for (const entry of cases) entry.expected = merge.mergeWatchedBy(entry.local, entry.incoming);
let disk = {};
const store = {};
vm.runInContext(
  modules[1],
  vm.createContext({
    exports: store,
    require: (name) => {
      if (name === "react") return {};
      assert.equal(name, "@/lib/profile-sync/watched-by-merge");
      return merge;
    },
    localStorage: {
      getItem: () => JSON.stringify(disk),
      setItem: (_key, value) => {
        disk = JSON.parse(value);
      },
    },
    Date: { now: () => 1000 },
  }),
  { timeout: 1000 },
);
store.recordWatchedBy("movie", "first");
store.recordWatchedBy("movie", "first");
store.recordWatchedBy("anime", "second");
const recorded = store.readWatchedByMap();
const fixture = { inputs, cases, recorded };
await writeFile(
  "ios/HarborTests/Fixtures/watched-by-reference.json",
  JSON.stringify(fixture, null, 2) + "\n",
);
await writeFile(
  "docs/ios/watched-by-sources.json",
  JSON.stringify(
    {
      reference: "0.9.132 (Beta)",
      final_beta_commit: "8274f05485554e531cf5654574de84108f16bdb7",
      final_archive_compared_normalized_bytes: true,
      final_beta_normalized_inputs: {
        "src/lib/profile-sync/watched-by-merge.ts":
          "369ed1ac65c51a517eb964537f5b70358af27f690695f1e2d219c6693c2999a6",
        "src/lib/watched-by.ts": "497a662e10f857031c981be64f6f00066f7010c9e542617bd0a55e0709054096",
      },
      inputs,
      original_functions_executed: true,
      vectors: cases.length,
      fixture_canonical_sha256: createHash("sha256").update(JSON.stringify(fixture)).digest("hex"),
      production_recording:
        "PlayerView after loaded, guarded by the original profile playback generation",
      production_surface:
        "Continue Watching: another known profile only, with the existing avatar and remove button",
      cloud_document: "account:watchedby",
      wire_profile_ids:
        "Unchanged Desktop device profile IDs; unknown IDs retained but never guessed",
      cloud_conflicts:
        "Per-media timestamp merge; equal clocks retain local, unlike whole-value layout conflicts",
      isolation:
        "Separate durable account and unsigned buckets; authenticated transport and caller generation checks",
      timestamp_eviction: 300,
      tied_eviction: "Deterministic key order for JSON objects without portable insertion order",
      full_desktop_parity_complete: false,
      ipa_created: false,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  JSON.stringify({ original_vectors: cases.length, original_recording_executed: true, inputs }),
);
