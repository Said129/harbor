import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const args = process.argv.slice(2);
const argument = (name) => {
  const index = args.indexOf(name);
  assert(index >= 0 && args[index + 1], "Missing " + name);
  return path.resolve(args[index + 1]);
};
const reference = argument("--reference"),
  dependency = argument("--dependency");
const inputs = {
  "src/lib/streams/plugins/adapter.ts":
    "257ddc205520ae9c1dae089e8764bfe5733a928c7512331b36433dd9de547a4f",
  "src/lib/manga/plugins/host-http.ts":
    "9f88ca743ef87f50d820fb4ca2573d1837d5418279f1284839bf34410245f589",
  "src/lib/same-site-host.ts": "3fc786aa3035c5f0f3ac5cfd4413968acd0376dc2ef5ecde104656aae11e6022",
  "src/lib/torrent/magnet.ts": "278bde3277b52408c5af11f812a6673801d020e2af32f2e8f2ebd73181d78789",
  "src/lib/privacy/blocklist.ts":
    "dad2a89a8856370cdb548b1062a997bb80664b20665b0465ddc2e9a8312422c4",
  "package.json": "ff5aed57316298a94db2749f543656646c23807c6271de1fbdbcab5af76ce9ce",
};
const digest = (value) => createHash("sha256").update(value).digest("hex");
const sources = {};
for (const [name, hash] of Object.entries(inputs)) {
  const source = (await readFile(path.join(reference, name), "utf8")).replaceAll("\r\n", "\n");
  assert.equal(digest(source), hash, name);
  sources[name] = source;
}
assert.equal(JSON.parse(sources["package.json"]).dependencies.tldts, "7.4.12");
const suffixProgram = await readFile(path.join(dependency, "index.umd.min.js"), "utf8");
const license = await readFile(path.join(dependency, "LICENSE"));
assert.equal(
  digest(suffixProgram),
  "202d92c731736e54220874e8dd0bdc469a01e773836b4a87169cd05a2c8dd558",
);
assert.equal(digest(license), "c64182d48160db948b6aa97a984f1a32974ce4d2053900361264cd33853796cb");
assert.equal(
  JSON.parse(await readFile(path.join(dependency, "package.json"), "utf8")).version,
  "7.4.12",
);

function program(name, selected) {
  const tree = ts.createSourceFile(name, sources[name], ts.ScriptTarget.Latest, true);
  assert.equal(tree.parseDiagnostics.length, 0);
  const nodes = tree.statements.filter((node) =>
    selected
      ? ts.isFunctionDeclaration(node) && selected.includes(node.name?.text)
      : !ts.isImportDeclaration(node) &&
        !ts.isExportDeclaration(node) &&
        !ts.isInterfaceDeclaration(node) &&
        !ts.isTypeAliasDeclaration(node),
  );
  if (selected) assert.equal(nodes.length, selected.length);
  const plain = nodes.map((node) => node.getText(tree).replace(/^export\s+/, "")).join("\n");
  const result = ts.transpileModule(plain, {
    fileName: name,
    reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.ES2020 },
  });
  assert.equal(result.diagnostics?.length ?? 0, 0);
  assert(!/^\s*(?:import|export)\s/m.test(result.outputText));
  return result.outputText;
}
const privacy = program("src/lib/privacy/blocklist.ts");
const safe = program("src/lib/manga/plugins/host-http.ts", [
  "isPrivateV4",
  "embeddedV4",
  "isPrivateHost",
  "assertSafeUrl",
]);
const magnet = program("src/lib/torrent/magnet.ts");
const sameSite = program("src/lib/same-site-host.ts");
const adapter = program("src/lib/streams/plugins/adapter.ts");
const source = `(() => {
${suffixProgram}
const privacy = (() => { ${privacy}\nreturn {isBlockedUrl,setTrackerBlocking}; })();
const network = (() => { const {isBlockedUrl}=privacy; ${safe}\nreturn {assertSafeUrl}; })();
const magnet = (() => { ${magnet}\nreturn {parseMagnet,infoHashFromSources}; })();
const sites = (() => { const parse=globalThis.tldts.parse; ${sameSite}\nreturn {sameSiteHost}; })();
const adapter = (() => { const {assertSafeUrl}=network; const {sameSiteHost}=sites;
const {parseMagnet,infoHashFromSources}=magnet; ${adapter}\nreturn {toStreams}; })();
globalThis.harborAdaptPluginStreams = function(text) {
 const input=JSON.parse(text);
 privacy.setTrackerBlocking(input.blockTrackers !== false);
 return JSON.stringify(adapter.toStreams(input.rawJSON === undefined ? input.raw : JSON.parse(input.rawJSON),input.context));
};
})();`;
const context = vm.createContext({ URL });
new vm.Script(source).runInContext(context, { timeout: 2000 });
const req = {
  type: "movie",
  id: "tt0133093",
  ids: ["tt0133093"],
  imdbId: "tt0133093",
  tmdb: null,
  title: "The Matrix",
  year: 1999,
  season: null,
  episode: null,
  absoluteEpisode: null,
  settings: {},
};
const base = {
  req,
  addonId: "owned.plugin",
  addonName: "Owned repository",
  addonUrl: "harbor-plugin://owned.plugin",
  pluginName: "Owned plugin",
};
const row = (name, raw, extra = {}, override = {}) => ({
  name,
  input: { raw, context: { ...base, ...extra }, ...override },
});
const hash = "0123456789abcdef0123456789abcdef01234567";
const cases = [
  row("direct-quality-language-size-headers-and-subtitles", [
    {
      url: "https://cdn.example.org/movie.m3u8",
      quality: "FHD",
      language: ["English", "Japanese"],
      size: "1,5 GB",
      provider: "Owned",
      headers: {
        Referer: "https://video.example.org/page",
        Origin: "https://example.org",
        Authorization: "owned",
        Connection: "close",
        "X-Harbor-Key": "drop",
      },
      subtitles: [{ url: "https://cdn.example.org/owned.srt", language: "es", id: 7 }],
    },
  ]),
  row(
    "private-and-invalid-protocols-are-rejected",
    [
      "http://127.1/a",
      "http://localhost/a",
      "http://[::1]/a",
      "http://[::ffff:127.0.0.1]/a",
      "http://[64:ff9b::7f00:1]/a",
      "file:///owned",
      "javascript:owned",
      "https://owned.local/a",
    ].map((url) => ({ url })),
  ),
  row("tracking-default-block", [{ url: "https://google-analytics.com/owned" }]),
  row(
    "tracking-user-disabled",
    [{ url: "https://google-analytics.com/owned" }],
    {},
    { blockTrackers: false },
  ),
  row("tracking-default-restored-after-previous-call", [
    { url: "https://google-analytics.com/owned" },
  ]),
  row("private-public-suffix-headers", [
    {
      url: "https://one.github.io/owned",
      headers: {
        Referer: "https://two.github.io/page",
        Origin: "https://two.github.io",
        "User-Agent": "owned",
        Cookie: "owned=1",
      },
    },
  ]),
  row("ordinary-public-suffix-shares-site", [
    {
      url: "https://cdn.example.co.uk/owned",
      headers: { Referer: "https://video.example.co.uk/page", Origin: "https://example.co.uk" },
    },
  ]),
  row("header-values-controls-commas-and-limit", [
    {
      url: "https://example.org/owned",
      headers: {
        Host: "drop",
        "Content-Length": "5",
        "X-Bad": "a,b",
        "X-Control": "before\r\nafter",
        ...Object.fromEntries(
          Array.from({ length: 30 }, (_, index) => ["X-Owned-" + index, "v" + index]),
        ),
      },
    },
  ]),
  row("magnet-trackers-dht-and-file-index", [
    {
      url:
        "magnet:?xt=urn:btih:" +
        hash +
        "&tr=" +
        encodeURIComponent("udp://tracker.example.org:80/announce"),
      fileIdx: 2,
      seeders: 7.6,
    },
  ]),
  row("base32-magnet", [{ url: "magnet:?xt=urn:btih:ABCDEFGHIJKLMNOPQRSTUVWXYZ234567" }]),
  row("infohash-priority-over-direct-and-sources", [
    {
      url: "https://example.org/owned.mkv",
      infoHash: hash.toUpperCase(),
      fileIdx: 0,
      sources: ["tracker:udp://tracker.example.org:80"],
    },
  ]),
  row("hash-in-sources-and-external-youtube", [
    { sources: ["dht:" + hash] },
    { externalUrl: "https://example.org/owned" },
    { ytId: "dQw4w9WgXcQ" },
  ]),
  row("object-stream-envelope-and-malformed-items", {
    streams: [
      null,
      7,
      "owned",
      {},
      { url: "https://example.org/owned", name: { x: 1 }, title: 12, description: ["one", "two"] },
    ],
  }),
  row(
    "first-150-valid-streams",
    Array.from({ length: 170 }, (_, index) =>
      index < 10 ? {} : { url: "https://example.org/" + index },
    ),
  ),
  row(
    "continuous-anime-visible-filename",
    [{ url: "https://example.org/owned", quality: "1080p", language: "Japanese" }],
    { req: { ...req, type: "series", title: "Owned anime", year: null, absoluteEpisode: 99 } },
  ),
  row(
    "actual-source-season-and-episode-filename",
    [{ url: "https://example.org/owned", quality: "720p" }],
    {
      req: {
        ...req,
        type: "series",
        title: "Owned series",
        season: 5,
        episode: 23,
        absoluteEpisode: 99,
      },
    },
  ),
  row("subtitle-limit-and-safe-urls", [
    {
      url: "https://example.org/owned",
      subtitles: [
        { url: "http://127.0.0.1/secret.srt" },
        ...Array.from({ length: 45 }, (_, index) => ({
          url: "https://example.org/" + index + ".vtt",
          lang: "es",
        })),
      ],
    },
  ]),
  row("title-evidence-keeps-original-filename", [
    {
      url: "https://example.org/owned",
      filename: "The.Matrix.1999.1080p.mkv",
      size: 1000,
      bingeGroup: "owned",
      expiresAt: 12345,
    },
  ]),
  row("text-and-language-bounds", [
    {
      url: "https://example.org/owned",
      name: "n".repeat(180),
      title: "t".repeat(500),
      description: "d".repeat(500),
      language: ["es", "en", "ja", "fr", "de"],
    },
  ]),
  row("absent-or-malformed-envelope", { streams: "owned" }),
];
for (const test of cases) {
  test.input.rawJSON = JSON.stringify(test.input.raw);
  test.expected = JSON.parse(context.harborAdaptPluginStreams(JSON.stringify(test.input)));
}
assert.equal(cases.length, 20);
assert.deepEqual(cases[1].expected, []);
assert.deepEqual(cases[2].expected, []);
assert.equal(cases[3].expected.length, 1);
assert.deepEqual(cases[4].expected, []);
assert.equal(cases[5].expected[0].behaviorHints.proxyHeaders.request.Referer, undefined);
assert.equal(
  cases[6].expected[0].behaviorHints.proxyHeaders.request.Referer,
  "https://video.example.co.uk/page",
);
assert.equal(cases[13].expected.length, 150);
assert.equal(cases[14].expected[0].behaviorHints.filename, "Owned anime E99 1080p Japanese");
assert.equal(cases[15].expected[0].behaviorHints.filename, "Owned series S05E23 720p");
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs,
  thirdParty: {
    name: "tldts",
    version: "7.4.12",
    programSha256: digest(suffixProgram),
    licenseSha256: digest(license),
    integrity:
      "sha512-WylhSDKVeYnWXL3a+vKTaOxjnOeEGw938hImY8zoRWJjRRK/Jp1K+IihBzIONpUmW4e3WmXT6q5FW6vlESVZCA==",
  },
  program: { source, sha256: digest(source) },
};
const fixture = { reference: asset.reference, programSha256: asset.program.sha256, cases };
for (const [name, value] of [
  ["ios/Harbor/PluginStreamAdapterAssets.json", asset],
  ["ios/HarborTests/Fixtures/plugin-stream-adapter-reference.json", fixture],
]) {
  const file = path.join(root, name);
  if (args.includes("--check")) assert.deepEqual(JSON.parse(await readFile(file, "utf8")), value);
  else await writeFile(file, JSON.stringify(value, null, 2) + "\n");
}
const licenseFile = path.join(root, "ios/Harbor/TLDTS-LICENSE.txt");
if (args.includes("--check")) assert.deepEqual(await readFile(licenseFile), license);
else await writeFile(licenseFile, license);
process.stdout.write(
  JSON.stringify({
    referenceCases: cases.length,
    nativeExecuted: false,
    programBytes: Buffer.byteLength(source),
    programSha256: asset.program.sha256,
  }) + "\n",
);
