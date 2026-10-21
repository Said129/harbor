import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const argument = process.argv.indexOf("--reference");
assert(argument >= 0 && process.argv[argument + 1]);
const reference = path.resolve(process.argv[argument + 1]);
const commit = "0834340cec5531650bfe78cd628628702e636987";
const digest = (value) => createHash("sha256").update(value).digest("hex");
const inputs = {
    "src/lib/manga/plugins/adapter.ts":
      "2c18c89716a0dab55fa3a7ebab73027d6d2a04e69018c1ed8baa8ea6fc6c6900",
    "src/lib/manga/plugins/repo.ts":
      "cc7a6959e8f4a50b4369f18dac0bbbe169486844fc79ab90253475359b8454ae",
    "src/lib/manga/sources/mangayomi/repo.ts":
      "3eef1001dd8adcfd226a540a7cff5b286ac732f951e3964d5bf7e2a2295cb64e",
    "src/lib/manga/sources/mangayomi/prelude.ts":
      "803b41058fc320ab9c5c4fb6668b8ddb7c93c96963b20f093404e6ab70ff7fa2",
    "src/lib/manga/sources/mangayomi/prelude/dom.ts":
      "392f0829cd4f8f2eef9fd09b8603cfd658eca60af4dcf2d794a6bc20cb4be739",
    "src/lib/manga/sources/mangayomi/prelude/crypto.ts":
      "8a59231b823e456abc432f5510e1d32f7f3eb116bc218c207231cb03f372618b",
    "src/lib/manga/sources/mangayomi/prelude/runtime.ts":
      "1ae6afb69b393b99462f1b76bc4f4d1526d863d62eb588c028009682e16c741e",
    "src/lib/manga/model.ts": "89d34525da5a42c1f6ce228cb96fe4805e30ad8d9c0ca8c9d5d0697c251db662",
    "src/lib/ebook/extensions.ts":
      "146fdfdf7b3cc9188b1410e0ad8df7b84f0724db3c0cefad3eb4c03080df3795",
    "src/lib/ebook/providers.ts":
      "1ef74e529709b18e54490c22a1dfbd2c6274e0479b1d9d8aefb8941956d38f65",
  },
  sources = {};
for (const [name, hash] of Object.entries(inputs)) {
  const source = (await readFile(path.join(reference, name), "utf8")).replaceAll("\r\n", "\n");
  assert.equal(digest(source), hash, name);
  sources[name] = source;
}
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
  const output = ts.transpileModule(plain, {
    fileName: name,
    reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.ES2020 },
  });
  assert.equal(output.diagnostics?.length ?? 0, 0);
  assert(!/^\s*(?:import|export)\s/m.test(output.outputText));
  return output.outputText;
}
const manga = program("src/lib/manga/plugins/adapter.ts");
const repo = program("src/lib/manga/plugins/repo.ts", [
  "isJsLang",
  "isDartLang",
  "foreignEntryArray",
  "codeLocation",
  "looksManga",
  "isMangayomiEntry",
  "isImportableMangayomi",
  "langCount",
  "classifyForeign",
  "toManifest",
]);
const index = program("src/lib/manga/sources/mangayomi/repo.ts", [
  "isJsLang",
  "isDartLang",
  "codeLocation",
  "looksManga",
  "isImportableEntry",
  "isJsEntry",
  "entryArray",
  "pickLangId",
  "normalizeEntry",
  "expandEntry",
  "parseMangayomiIndex",
  "fold32",
  "entryId",
  "dedupeVariants",
]);
const ebookRepo = program("src/lib/ebook/extensions.ts", ["manifest"]);
const ebook = program("src/lib/ebook/providers.ts", [
  "routeId",
  "record",
  "text",
  "scalarText",
  "positiveInt",
  "titleVolume",
  "sourceTitle",
  "url",
  "pluginEBook",
  "pluginChapters",
  "pluginContent",
  "cleanSourceText",
]);
const constants = ["dom", "crypto", "runtime"]
  .map((name) => program("src/lib/manga/sources/mangayomi/prelude/" + name + ".ts"))
  .join("\n");
assert.match(sources["src/lib/manga/model.ts"], /export const MANGA_PAGE = 48;/);
const composer = program("src/lib/manga/sources/mangayomi/prelude.ts");
const source = `var plugin = (() => {
const manga=(()=>{${manga}\nreturn {toSummaries,toSummary,toChapters,toPages,toTags};})();
const repos=(()=>{${repo}\nreturn {toManifest,classifyForeign};})();
const indices=(()=>{${index}\nreturn {parseMangayomiIndex,entryId,dedupeVariants};})();
const ebookRepos=(()=>{${ebookRepo}\nreturn {manifest};})();
const ebook=(()=>{${ebook}\nreturn {pluginEBook,pluginChapters,pluginContent};})();
const compose=(()=>{const MANGA_PAGE=48;${constants}\n${composer}\nreturn buildMangayomiSource;})();
function repository(input) {
 const root=input.raw && typeof input.raw==='object' ? input.raw : {};
 const rows=Array.isArray(root.plugins) ? root.plugins : [];
 const ebookRoot=['ebook','novel'].includes(root.type)||['ebook','novel'].includes(root.mediaType);
 const native=rows.map(row=>input.kind==='ebook' ? ebookRepos.manifest(row,ebookRoot) : repos.toManifest(row)).filter(Boolean);
 const foreign=input.kind==='manga' && !native.length ? repos.classifyForeign(input.raw) : null;
 const entries=native.map(row=>({...row,format:'harbor'}));
 if (foreign?.kind==='mangayomi') {
  for (const row of indices.dedupeVariants(indices.parseMangayomiIndex(input.raw))) entries.push({
    id:indices.entryId(row,input.url),name:row.name,version:row.version,lang:row.lang,nsfw:row.isNsfw===true,
    icon:row.iconUrl,entry:row.sourceCodeUrl,format:'mangayomi',baseUrl:row.baseUrl.replace(/\\/+$/,''),apiUrl:(row.apiUrl||'').replace(/\\/+$/,'')});
 }
 return {name:typeof root.name==='string' ? root.name : 'Repository',entries,foreign};
}
return {id:'harbor.trusted.reading',name:'Harbor reading adapters',content:function(input) {
 switch(input.operation) {
 case 'repository':return repository(input);
 case 'manga-books':return manga.toSummaries(input.raw);
 case 'manga-detail':return manga.toSummary(input.raw);
 case 'manga-chapters':return manga.toChapters(input.raw);
 case 'manga-pages':return manga.toPages(input.raw,input.baseUrl);
 case 'manga-tags':return manga.toTags(input.raw);
 case 'ebook-books':return (Array.isArray(input.raw)?input.raw:[]).map(value=>ebook.pluginEBook(input.provider,value)).filter(Boolean);
 case 'ebook-detail':return ebook.pluginEBook(input.provider,input.raw);
 case 'ebook-chapters':return ebook.pluginChapters(input.raw);
 case 'ebook-content':return ebook.pluginContent(input.raw);
 case 'mangayomi-source':return compose(input.raw);
 default:throw new Error('Unknown reading adapter operation');
 }
}};})();`;
const context = vm.createContext({ URL });
new vm.Script(source).runInContext(context, { timeout: 2000 });
const cases = [];
const row = (name, operation, raw, extra = {}) => {
  const input = { operation, raw, ...extra };
  const expected = JSON.parse(JSON.stringify(context.plugin.content(input)));
  cases.push({ name, input, expected });
  return expected;
};
assert.equal(
  row("manga-summary-clamps-and-rejects-invalid-cover", "manga-books", [
    { id: "a", title: "Title", cover: "javascript:bad", author: "Author" },
    { id: "bad" },
  ]).length,
  1,
);
assert.equal(
  row(
    "manga-summary-cap",
    "manga-books",
    Array.from({ length: 501 }, (_, i) => ({ id: String(i), title: "Book" })),
  ).length,
  500,
);
assert.equal(
  row("manga-detail", "manga-detail", {
    id: "owned",
    title: "Owned",
    year: 2020.9,
    description: "Description",
  }).year,
  2020,
);
assert.equal(
  row("manga-chapter-metadata", "manga-chapters", [
    { id: "ch", chapter: "3.5", volume: "2", language: "es", pages: 12.9 },
  ])[0].pages,
  12,
);
assert.deepEqual(row("manga-chapters-reject-missing-id", "manga-chapters", [{ title: "bad" }]), []);
assert.equal(
  row(
    "manga-page-aliases-and-headers",
    "manga-pages",
    [
      "https://cdn.example.org/a.jpg",
      {
        src: "https://cdn.example.org/b.jpg",
        headers: { Referer: "https://example.org/", Cookie: "private", "User-Agent": "Owned" },
      },
    ],
    { baseUrl: "https://example.org" },
  )[1].headers.cookie,
  undefined,
);
assert.deepEqual(
  row("manga-pages-reject-unsafe-protocol", "manga-pages", [
    "file:///private/a",
    { url: "javascript:bad" },
  ]),
  [],
);
assert.equal(
  row("manga-pages-reject-cross-site-and-control-headers", "manga-pages", [
    {
      url: "https://cdn.example.org/a.jpg",
      headers: { origin: "https://other.example.net", referer: "bad\nurl", "user-agent": "Owned" },
    },
  ])[0].headers.origin,
  undefined,
);
assert.equal(
  row("manga-tags", "manga-tags", [{ id: "a", name: "Adventure" }, { name: "invalid" }]).length,
  1,
);
assert.equal(
  row(
    "manga-native-repository",
    "repository",
    { name: "Owned", plugins: [{ id: "owned", name: "Owned", entry: "a.js" }, { id: "bad" }] },
    { kind: "manga", url: "https://example.org/repo.json" },
  ).entries.length,
  1,
);
assert.equal(
  row(
    "ebook-mixed-repository-filters-type",
    "repository",
    {
      plugins: [
        { id: "owned", name: "Owned", entry: "a.js", type: "ebook" },
        { id: "bad", name: "Bad", entry: "b.js" },
      ],
    },
    { kind: "ebook", url: "https://example.org/repo.json" },
  ).entries.length,
  1,
);
assert.equal(
  row(
    "ebook-novel-repository",
    "repository",
    { mediaType: "novel", plugins: [{ id: "owned", name: "Owned", entry: "a.js" }] },
    { kind: "ebook", url: "https://example.org/repo.json" },
  ).entries[0].lang,
  "en",
);
const foreign = [
  {
    id: 12,
    name: "Owned",
    baseUrl: "https://example.org",
    sourceCodeUrl: "a.js",
    sourceCodeLanguage: 1,
    langs: ["es", "en"],
  },
  { name: "Dart", baseUrl: "https://example.org", sourceCodeUrl: "b.dart", sourceCodeLanguage: 0 },
];
const foreignResult = row(
  "mangayomi-index-js-filter-expansion-and-deduplication",
  "repository",
  foreign,
  { kind: "manga", url: "https://example.org/repo.json" },
);
assert.equal(foreignResult.entries.length, 1);
assert.equal(foreignResult.entries[0].lang, "en");
assert.match(foreignResult.entries[0].id, /^my-/);
assert.equal(
  row(
    "tachiyomi-is-identified-for-server-route",
    "repository",
    [{ apk: "a.apk", pkg: "owned", sources: [{}, {}] }],
    { kind: "manga", url: "https://example.org/repo.json" },
  ).foreign.kind,
  "tachiyomi",
);
const provider = { id: "owned.books", name: "Owned books" };
assert.equal(
  row(
    "ebook-title-author-and-identity",
    "ebook-books",
    [
      {
        id: "a:b",
        title: "Owned_Book!",
        author: "Author",
        cover: "https://example.org/cover.jpg",
        openLibraryId: "/works/OL1W",
      },
    ],
    { provider },
  )[0].id,
  "source:owned.books:a%3Ab",
);
assert.deepEqual(
  row(
    "ebook-rejects-fanmade-and-empty-title",
    "ebook-books",
    [
      { id: "x", title: "Fan", isFanMade: true },
      { id: "bad", title: "!!!" },
    ],
    { provider },
  ),
  [],
);
assert.equal(
  row(
    "ebook-detail-aliases",
    "ebook-detail",
    { id: "owned", title: "Title", altTitles: ["Other"], authors: ["Author", " "], language: "ar" },
    { provider },
  ).authors.length,
  1,
);
assert.equal(
  row("ebook-nested-volumes", "ebook-chapters", [
    { title: "Volume 1", chapters: [{ id: "ch1", chapter: 1, title: "First" }] },
    { id: "ch2", chapter: "2" },
  ]).length,
  2,
);
assert.equal(
  row("ebook-volume-headings", "ebook-chapters", [
    { id: "volume", title: "Volume 2" },
    { id: "ch", title: "Owned" },
  ])[0].volume,
  "Volume 2",
);
assert.equal(
  row(
    "ebook-content-text-cleaning",
    "ebook-content",
    "Owned paragraph\r\nSecond paragraph\n document.querySelector('bad')",
  ).text,
  "Owned paragraph\nSecond paragraph",
);
assert.equal(
  row("ebook-content-aliases-and-image-protocols", "ebook-content", {
    body: "Owned",
    images: ["https://example.org/a.jpg", "file:///private"],
  }).images.length,
  1,
);
const mangayomiSource = row("mangayomi-original-composer", "mangayomi-source", {
  id: "my-owned",
  name: "Owned",
  lang: "en",
  baseUrl: "https://example.org",
  apiUrl: "",
  version: "1",
  isNsfw: false,
  source: "class DefaultExtension {getPopular(){return {list:[]};}}",
});
assert.match(mangayomiSource, /"pageSize":48/);
assert.match(mangayomiSource, /harbor.register\(__hyAdapt/);
const asset = { schema: 1, reference: commit, inputs, program: { source, sha256: digest(source) } };
await writeFile(
  path.join(root, "ios/Harbor/ReadingPluginAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
await writeFile(
  path.join(root, "ios/HarborTests/Fixtures/reading-plugin-reference.json"),
  JSON.stringify({ schema: 1, reference: commit, programSha256: digest(source), cases }, null, 2) +
    "\n",
);
console.log(
  JSON.stringify({
    reference: commit,
    inputs: Object.keys(inputs).length,
    executedCases: cases.length,
    programBytes: Buffer.byteLength(source),
    sha256: digest(source),
    nativeExecutionApproved: false,
  }),
);
