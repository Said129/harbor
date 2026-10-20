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
const inputs = {
  "src/lib/streams/plugins/manifest.ts":
    "f45b89c28dcf022ebb65400e6d94eee333d80a450de00935fd2a63d0ce346e1a",
  "src/lib/streams/plugins/types.ts":
    "f81d773a2d015a4dcdbf031ba477515131c676fc4c01f1100690f408975121dc",
};
const modules = new Map();
for (const [name, hash] of Object.entries(inputs)) {
  const source = (await readFile(path.join(reference, name), "utf8")).replaceAll("\r\n", "\n");
  assert.equal(createHash("sha256").update(source).digest("hex"), hash, name);
  const result = ts.transpileModule(source, {
    fileName: name,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    reportDiagnostics: true,
  });
  assert.equal(result.diagnostics?.length ?? 0, 0);
  modules.set(name, result.outputText);
}
const types = {};
vm.runInNewContext(
  modules.get("src/lib/streams/plugins/types.ts"),
  { exports: types },
  { timeout: 1000 },
);
const manifest = {};
vm.runInNewContext(
  modules.get("src/lib/streams/plugins/manifest.ts"),
  {
    exports: manifest,
    URL,
    require: (id) => {
      assert.equal(id, "./types");
      return types;
    },
  },
  { timeout: 1000 },
);
const resultOf = (operation) => {
  try {
    return { expected: JSON.parse(JSON.stringify(operation())) };
  } catch (error) {
    assert(error instanceof types.PluginError);
    return { error: error.code };
  }
};
const urls = [
  "example.org",
  " https://EXAMPLE.org:443/plugins/ ",
  "example.org/REPO.JSON?key=owned#fragment",
  "github.com/owned/repository",
  "https://github.com/owned/repository.git",
  "https://github.com/owned/repository/tree/develop/nested",
  "https://github.com/owned/repository/blob/main/list.json?raw=1#ignored",
  "https://raw.githubusercontent.com/owned/repository/HEAD/manifest.json",
  "https://example.org/a/../plugins",
  "https://example.org/a%20b?configured=true",
  "",
  "http://example.org/manifest.json",
  "cloudstreamrepo://owned",
  "https://",
].map((input) => ({
  input,
  ...resultOf(() => {
    const url = manifest.normalizeRepoUrl(input);
    return {
      url,
      candidates: manifest.repoUrlCandidates(url),
      name: manifest.repoDisplayName(url),
    };
  }),
}));
const base = "https://example.org/plugins/manifest.json";
const harbor = {
  type: "stream",
  plugins: [
    {
      id: "owned.one",
      name: " Owned One ",
      entry: "scripts/one.js",
      version: " 2.1 ",
      sha256: "AB".repeat(32),
      lang: [" en ", "", "ja", 8],
      types: ["FILM", "other", "movie"],
      idPrefixes: ["tmdb:"],
      hosts: ["CDN.Example.ORG"],
      settings: true,
      nsfw: true,
      platforms: ["ios", "desktop"],
      minHarbor: "0.9",
      timeoutMs: 90_000,
    },
    {
      id: "owned.two",
      name: "Owned Two",
      entry: "../two.js",
      version: 7,
      timeoutMs: -1,
      enabled: false,
      sha256: "invalid",
    },
    { id: "missing.name", entry: "missing.js" },
    null,
  ],
};
const provider = {
  name: "Repository",
  homepage: " https://example.org ",
  scrapers: [
    {
      filename: "folder/owned.js",
      version: "3",
      logo: "logo.png",
      contentLanguage: "es",
      supportedTypes: ["shows"],
      hasSettings: true,
      adult: true,
      supportedPlatforms: ["mobile"],
      supportedFormats: ["hls", "dash"],
      limited: true,
      notes: " owned note ",
    },
    {
      id: "explicit",
      name: "Explicit",
      filename: "https://cdn.example.org/explicit.js",
      enabled: false,
    },
  ],
};
const native = [
  {
    internalName: "owned.android",
    name: "Owned Android",
    url: "owned.cs3",
    apiVersion: 2,
    version: 5,
    status: 3,
    tvTypes: ["AnimeMovie", "Tv Series", "NSFW"],
    authors: ["One", "Two"],
    language: "en",
  },
  { internalName: "owned.android", url: "duplicate.cs3" },
  { url: "down.cs3?key=owned", status: 0 },
];
const manifests = [
  harbor,
  provider,
  provider.scrapers,
  native,
  {
    name: "Native",
    pluginLists: ["lists/one.json", { url: "lists/one.json" }, { url: "../two.json" }, ""],
  },
  { type: "ebook", plugins: [] },
  { type: "manga", plugins: [] },
  { id: "owned.addon", version: "1", resources: ["stream"], types: ["movie"] },
  { sources: [{ sourceCodeUrl: "owned.js" }] },
  { mangayomiSources: [{ pkgPath: "owned.js" }] },
  { type: "ebook" },
  {},
  [],
].map((input) => ({
  input,
  url: base,
  ...resultOf(() => manifest.parseStreamRepoManifest(input, base)),
}));
const ids = [
  base,
  "https://example.org/📚/manifest.json",
  "https://example.org/café/manifest.json",
].map((repository) => ({
  repository,
  entry: "owned.entry",
  expected: manifest.pluginIdFor(repository, "owned.entry"),
}));
const fixture = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs,
  urls,
  manifests,
  ids,
};
const target = path.join(root, "ios/HarborTests/Fixtures/plugin-manifest-reference.json");
if (args.includes("--check")) assert.deepEqual(JSON.parse(await readFile(target, "utf8")), fixture);
else await writeFile(target, JSON.stringify(fixture, null, 2) + "\n");
process.stdout.write(
  JSON.stringify({
    urls: urls.length,
    manifests: manifests.length,
    ids: ids.length,
    referenceExecuted: true,
    nativeExecuted: false,
  }) + "\n",
);
