import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(".");
const argument = process.argv.indexOf("--reference");
assert(argument > 0 && process.argv[argument + 1]);
const reference = path.resolve(process.argv[argument + 1]);
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
const inputs = {
  "src/views/anime/anime-rows.tsx":
    "bfc1be74fa1b20e2665ec5b67e1f5a640b1d188dd70bef24af425dabe8628e86",
  "src/lib/providers/jikan.ts": "b98c228d3db6f7aa0894574e1b06559c69389f0a3f80903ac75c3103f4923c9e",
};
const files = {};
for (const [file, digest] of Object.entries(inputs)) {
  const bytes = await readFile(path.join(reference, file));
  assert.equal(sha(bytes), digest, file);
  files[file] = ts.createSourceFile(
    file,
    bytes.toString("utf8").replaceAll("\r\n", "\n"),
    ts.ScriptTarget.Latest,
    true,
  );
  assert.equal(files[file].parseDiagnostics.length, 0);
}
const provider = files["src/lib/providers/jikan.ts"];
const names = new Set([
  "GENRE",
  "jikanAiringNow",
  "jikanUpcoming",
  "jikanTopAnime",
  "jikanTopAiring",
  "jikanTopPopular",
  "jikanTopMovies",
  "jikanTopTv",
  "jikanByGenre",
  "jikanByEra",
  "GEM_MEMBER_CEILING",
  "GEM_SCORED_BY_FLOOR",
  "SEQUEL_RX",
  "isSequelTitle",
  "jikanUnderratedGems",
]);
const extracted = provider.statements
  .filter((node) =>
    ts.isFunctionDeclaration(node)
      ? names.has(node.name?.text)
      : ts.isVariableStatement(node) &&
        node.declarationList.declarations.some((entry) => names.has(entry.name.getText(provider))),
  )
  .map((node) => node.getText(provider))
  .join("\n");
const rowsFile = files["src/views/anime/anime-rows.tsx"];
const declaration = rowsFile.statements
  .flatMap((node) => (ts.isVariableStatement(node) ? [...node.declarationList.declarations] : []))
  .find((entry) => entry.name.getText(rowsFile) === "SPECS");
assert(declaration?.initializer);
const javascript = ts.transpileModule(
  extracted + "\nconst SPECS=" + declaration.initializer.getText(rowsFile) + ";",
  {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  },
).outputText;
let requests = [],
  raw = [];
const context = vm.createContext({
  exports: {},
  Map,
  Set,
  jikanQuery(route, parameters) {
    requests.push({ route, parameters });
    return Promise.resolve([]);
  },
  fetchRawAnimePage(parameters) {
    requests.push({ route: "/anime", parameters });
    return Promise.resolve(raw);
  },
  metasFromJikan: async (items) => items,
  catalogGet: () => null,
  catalogSet() {},
  inflight: new Map(),
});
vm.runInContext(javascript, context);
const originals = vm.runInContext("SPECS", context);
assert.equal(originals.length, 20);
const rows = [];
for (const spec of originals) {
  requests = [];
  await spec.fetcher(1);
  const first = structuredClone(requests);
  requests = [];
  await spec.fetcher(3);
  const third = structuredClone(requests);
  assert.equal(first.length, third.length);
  const plans = first.map((request, index) => {
    const later = third[index];
    assert.equal(request.route, later.route);
    const factor = (later.parameters.page - request.parameters.page) / 2;
    const offset = request.parameters.page - factor;
    assert([1, 2].includes(factor) && Number.isInteger(offset));
    const parameters = Object.fromEntries(
      Object.entries(request.parameters)
        .filter(([key]) => key !== "page")
        .map(([key, value]) => [key, String(value)]),
    );
    return { path: request.route.slice(1), parameters, factor, offset };
  });
  rows.push({
    key: spec.key,
    title: spec.title,
    ranked: spec.rank === true,
    pool: spec.pool ?? "general",
    plans,
    filter: spec.key === "gems" ? "gems" : "none",
  });
}
assert.equal(new Set(rows.map((row) => row.key)).size, 20);
const payload = JSON.stringify({
  rows,
  sequelPattern: vm.runInContext("SEQUEL_RX.source", context),
  memberCeiling: vm.runInContext("GEM_MEMBER_CEILING", context),
  scoredByFloor: vm.runInContext("GEM_SCORED_BY_FLOOR", context),
});
await writeFile(
  path.join(root, "ios/Harbor/DesktopAnimeRowLabels.json"),
  JSON.stringify(
    { keys: [...new Set([...rows.map((row) => row.title), "Top 10 {name}"])].sort() },
    null,
    2,
  ) + "\n",
);
await writeFile(
  path.join(root, "ios/Harbor/DesktopAnimeRows.json"),
  JSON.stringify(
    {
      schema: 1,
      reference: "0834340cec5531650bfe78cd628628702e636987",
      inputs,
      payload,
      sha256: sha(payload),
    },
    null,
    2,
  ) + "\n",
);
raw = [
  { mal_id: 1, title: "Owned hidden original", members: 349999, scored_by: 4000, score: 8.1 },
  { mal_id: 2, title: "Too popular", members: 350001, scored_by: 5000, score: 9.2 },
  { mal_id: 3, title: "Too few ratings", members: 600, scored_by: 3999, score: 9.3 },
  { mal_id: 4, title: "Owned Season 2", members: 600, scored_by: 5000, score: 9.4 },
  {
    mal_id: 5,
    title_english: "Owned II",
    title: "Owned alternate",
    members: 600,
    scored_by: 5000,
    score: 9.5,
  },
  { mal_id: 6, title: "Owned at ceiling", members: 350000, scored_by: 4000, score: 8.8 },
  { mal_id: 7, title: "Owned oldest", members: 10000, scored_by: 6000, score: 7.8 },
];
requests = [];
const filtered = await context.exports.jikanUnderratedGems(2);
assert.deepEqual(
  Array.from(filtered, (row) => row.mal_id),
  [6, 1, 7],
);
await writeFile(
  path.join(root, "ios/HarborTests/Fixtures/anime-row-reference.json"),
  JSON.stringify(
    {
      inputs,
      payload_sha256: sha(payload),
      rows,
      gems: { input: raw, expectedIDs: Array.from(filtered, (row) => row.mal_id) },
    },
    null,
    2,
  ) + "\n",
);
await writeFile(
  path.join(root, "docs/ios/anime-row-sources.json"),
  JSON.stringify(
    {
      reference_version: "0.9.132",
      inputs,
      payload_sha256: sha(payload),
      original_row_count: rows.length,
      extracted_original_requests: true,
      gems_oracle_executed_without_network: true,
      apple_tests_executed: false,
      full_anime_parity_complete: false,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  JSON.stringify({
    originalAnimeRows: rows.length,
    payloadSHA256: sha(payload),
    originalGemsOracle: "pass",
    providerRequestsExecuted: 0,
  }),
);
