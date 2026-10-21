import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

const args = process.argv.slice(2),
  index = args.indexOf("--reference");
assert(index >= 0 && args[index + 1]);
const source = (
  await readFile(path.join(args[index + 1], "src/lib/streams/plugins/request.ts"), "utf8")
).replaceAll("\r\n", "\n");
const sourceHash = createHash("sha256").update(source).digest("hex");
assert.equal(sourceHash, "cdfe17a2ba63ccd0e44f774cd498fb538d66823360c8928844798d6131af49b0");
const tree = ts.createSourceFile("request.ts", source, ts.ScriptTarget.Latest, true);
assert.equal(tree.parseDiagnostics.length, 0);
const plain = tree.statements
  .filter((node) => !ts.isImportDeclaration(node) && !ts.isTypeAliasDeclaration(node))
  .map((node) => node.getText(tree).replace(/^export\s+/, ""))
  .join("\n");
const code = ts.transpileModule(plain, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.ES2020 },
}).outputText;
const movie = { id: "tt0133093", type: "movie", name: "The Matrix", releaseInfo: "1999" };
const show = {
  id: "tt3398540",
  type: "series",
  name: "Dragon Ball Super",
  releaseInfo: "2015–2018",
};
const make = (name, media, ids, pickedID, episode = null, meta = {}, tmdb = null, key = "") => ({
  name,
  input: { media, ids, pickedID, episode, meta, tmdb, key },
});
const cases = [
  make("movie-public-tmdb-without-personal-key", movie, [movie.id], movie.id, null, {
    moviedb_id: 603,
  }),
  make(
    "raw-season-five-episode-23-and-absolute-99",
    show,
    ["kitsu:9979:99", "tt3398540:5:23"],
    "kitsu:9979:99",
    {
      id: "kitsu:9979:99",
      season: 5,
      episode: 23,
      displaySeason: 1,
      displayEpisode: 99,
      absoluteNumber: 99,
    },
    { moviedb_id: 62715 },
  ),
  make("special-season-zero", show, ["tt3398540:0:2"], "tt3398540:0:2", null, {
    moviedb_id: 62715,
  }),
  make("explicit-tv-tmdb", show, ["tmdb:tv:62715:5:23"], "tmdb:tv:62715:5:23"),
  make("implicit-movie-tmdb", movie, ["tmdb:603"], "tmdb:603"),
  make("explicit-tmdb-kind-overrides-surface", show, ["tmdb:movie:603"], "tmdb:movie:603"),
  make(
    "declared-prefix-parses-numeric-leading-part",
    movie,
    ["tmdb:movie:603extra"],
    "tmdb:movie:603extra",
  ),
  make(
    "empty-title-falls-back-to-cinemeta",
    { ...movie, name: "  ", releaseInfo: null },
    [movie.id],
    movie.id,
    null,
    { moviedb_id: 603, name: "  The Matrix  ", releaseInfo: "1999–" },
  ),
  make(
    "configured-tmdb-find-precedes-cinemeta-mapping",
    movie,
    [movie.id],
    movie.id,
    null,
    { moviedb_id: 999 },
    { id: 603, kind: "movie" },
    "owned-fixture-key",
  ),
  make(
    "anime-name-and-verified-imdb-context",
    { ...show, id: "kitsu:9979", type: "anime", imdbID: "tt3398540" },
    ["kitsu:9979:99", "tt3398540:5:23"],
    "kitsu:9979:99",
    { id: "kitsu:9979:99", season: 5, episode: 23, name: "Episode name", absoluteNumber: 99 },
    { moviedb_id: 62715 },
  ),
  make(
    "unmapped-kitsu-keeps-raw-coordinates",
    { ...show, id: "kitsu:9979", type: "anime" },
    ["kitsu:9979:99"],
    "kitsu:9979:99",
    { id: "kitsu:9979:99", season: 1, episode: 99, absoluteNumber: 99 },
  ),
  make(
    "selected-episode-imdb-context-precedes-series",
    { ...show, imdbID: "tt1111111" },
    ["tt3398540:5:23"],
    "tt3398540:5:23",
    { id: "tt3398540:5:23", season: 5, episode: 23, imdbID: "tt3398540" },
    { moviedb_id: 62715 },
  ),
];
for (const row of cases) {
  const { media, ids, pickedID, episode, meta, tmdb } = row.input;
  const type = media.type === "anime" || media.type === "series" ? "series" : "movie";
  const context = {
    imdbId: episode?.imdbID ?? media.imdbID ?? null,
    title: media.name,
    year: parseInt(media.releaseInfo ?? "", 10) || null,
    season: episode?.season ?? null,
    episode: episode?.episode ?? null,
    absoluteEpisode: episode?.absoluteNumber ?? null,
  };
  const sandbox = vm.createContext({
    localStorage: { getItem: () => null, setItem() {} },
    cinemetaMeta: async () => meta,
    tmdbIdFromImdb: async () => (tmdb ? `tmdb:${tmdb.kind}:${tmdb.id}` : null),
    settingsValuesFor: () => ({}),
    parseCapstanId: () => null,
  });
  vm.runInContext(code, sandbox);
  row.expected = JSON.parse(
    JSON.stringify(
      await sandbox.buildPluginRequest({ type, ids, context }, pickedID, {}, row.input.key),
    ),
  );
}
assert.equal(cases[1].expected.season, 5);
assert.equal(cases[1].expected.episode, 23);
assert.equal(cases[1].expected.absoluteEpisode, 99);
assert.equal(cases[9].expected.title, "Dragon Ball Super");
assert.equal(cases[9].expected.imdbId, "tt3398540");
const fixture = {
  reference: "0834340cec5531650bfe78cd628628702e636987",
  input: "src/lib/streams/plugins/request.ts",
  sourceHash,
  cases,
};
const target = "ios/HarborTests/Fixtures/plugin-stream-requests-reference.json";
if (args.includes("--check")) assert.deepEqual(JSON.parse(await readFile(target, "utf8")), fixture);
else await writeFile(target, JSON.stringify(fixture, null, 2) + "\n");
console.log(JSON.stringify({ referenceCases: cases.length, sourceHash, nativeExecuted: false }));
