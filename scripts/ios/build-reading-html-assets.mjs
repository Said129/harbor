import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { load } from "cheerio";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const index = process.argv.indexOf("--reference");
assert(index >= 0 && process.argv[index + 1]);
const reference = path.resolve(process.argv[index + 1]);
const digest = (value) => createHash("sha256").update(value).digest("hex");
const inputs = {
  "src/lib/manga/sources/html.ts":
    "40c0c21ea7a6aaf62b6d7c97df58a22e4eff8e8d1b31b5ead450b32e1433f822",
  "src/lib/manga/types.ts": "028c01c96dc23fd14ab5b1f199955306e35f0fc36d016389238d7790bdd5db27",
  "src/lib/manga/sources.ts": "eaba0b4a104731969ec73f878225e59ec61f29f8d211d3657af2c87715a4c0bc",
  "src/lib/ebook/sources.ts": "bb35073beaa8c0cf5daa2233728d5a27e5a94f453cd781cfc2ceed5d0971ecee",
  "src/lib/ebook/providers.ts": "1ef74e529709b18e54490c22a1dfbd2c6274e0479b1d9d8aefb8941956d38f65",
};
const sources = {};
for (const [name, hash] of Object.entries(inputs)) {
  sources[name] = (await readFile(path.join(reference, name), "utf8")).replaceAll("\r\n", "\n");
  assert.equal(digest(sources[name]), hash, name);
}
function extract(name, names) {
  const tree = ts.createSourceFile(name, sources[name], ts.ScriptTarget.Latest, true);
  assert.equal(tree.parseDiagnostics.length, 0);
  const selected = tree.statements.filter(
    (node) => ts.isFunctionDeclaration(node) && names.includes(node.name?.text),
  );
  assert.equal(selected.length, names.length);
  return ts.transpileModule(
    selected.map((node) => node.getText(tree).replace(/^export\s+/, "")).join("\n"),
    {
      fileName: name,
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None },
    },
  ).outputText;
}
const manga =
  extract("src/lib/manga/types.ts", ["mangaThrottle"]) +
  extract("src/lib/manga/sources/html.ts", [
    "str",
    "parseHtmlConfig",
    "selectorOf",
    "makeHtmlProvider",
    "resolveFavicon",
  ]) +
  extract("src/lib/manga/sources.ts", ["addHtmlSource"]);
const ebook =
  extract("src/lib/ebook/sources.ts", ["sourceId", "parseEBookSourceConfig"]) +
  extract("src/lib/ebook/providers.ts", [
    "routeId",
    "text",
    "sourceTitle",
    "cleanSourceText",
    "htmlProvider",
  ]);
const source = `(function(){
  return function createReadingHTML(payload,http){
    const input=JSON.parse(payload.source);
    const safeFetch=async(url,opts)=>{
      const result=await http({url:String(url),opts:{...(opts??{}),responseType:"text"}});
      return {ok:result.ok===true,status:result.status,text:async()=>String(result.body??"")};
    };
    const manga=(()=>{const MANGA_PAGE=48;const readCustom=()=>[];const writeCustom=()=>true;const notify=()=>{};
      ${manga}\nreturn {parseHtmlConfig,addHtmlSource,makeHtmlProvider,resolveFavicon};})();
    const ebook=(()=>{const htmlPages=new Map();${ebook}\nreturn {sourceId,parseEBookSourceConfig,htmlProvider};})();
    let config,record,provider;
    if(input.kind==="manga"){
      config=manga.parseHtmlConfig(input.raw);
      if(!config) throw new Error("Invalid HTML source config");
      record=manga.addHtmlSource(config);
      provider=manga.makeHtmlProvider(record.id,config);
    }else if(input.kind==="ebook"){
      config=ebook.parseEBookSourceConfig(input.raw);
      record={id:ebook.sourceId("html",config.baseUrl),name:config.name,iconUrl:config.iconUrl,config};
      provider=ebook.htmlProvider(record);
    }else throw new Error("Invalid reading source kind");
    const meta={id:record.id,name:record.name,icon:record.iconUrl,config,hasTags:false,hasSettings:false};
    return {
      meta,
      async prepare(){if(input.kind==="manga"&&input.resolveIcon&&!config.iconUrl){config.iconUrl=await manga.resolveFavicon(config.baseUrl);meta.icon=config.iconUrl;}},
      call(method,args){if(typeof provider[method]!=="function")throw new Error("no method: "+method);return provider[method](...args);}
    };
  };
})()`;
new vm.Script(source);
class HTMLNode {
  constructor($, node) {
    this.$ = $;
    this.node = node;
  }
  querySelector(selector) {
    const node = this.$(this.node).find(selector).first()[0];
    return node ? new HTMLNode(this.$, node) : null;
  }
  querySelectorAll(selector) {
    return this.$(this.node)
      .find(selector)
      .toArray()
      .map((node) => new HTMLNode(this.$, node));
  }
  getAttribute(name) {
    return this.$(this.node).attr(name) ?? null;
  }
  get textContent() {
    return this.$(this.node).text();
  }
}
class Parser {
  parseFromString(html) {
    const $ = load(html);
    return new HTMLNode($, $.root()[0]);
  }
}
const factory = vm.runInNewContext(source, {
  DOMParser: Parser,
  URL,
  setTimeout,
  Promise,
  window: {
    setTimeout: (...args) => {
      const timer = setTimeout(...args);
      timer.unref();
      return timer;
    },
  },
});
const requests = [];
const catalog = `<section><article class="card"><a class="title" href="/book/one">The Book</a><img data-src="/cover.png"></article><article class="card"><a class="title" href="/book/two">Second Book</a></article></section>`;
const detail = `<h1>The Book</h1><a class="author">Owned author</a><p class="summary">Owned description</p><span class="status">Ongoing</span><div class="chapters"><a href="/chapter/one"><span class="num">1.5</span><span class="name">Chapter One</span></a><a href="/chapter/two"><span class="num">2</span><span class="name">Chapter Two</span></a></div>`;
const chapter = `<main class="reader"><h1>Owned heading</h1><p>First paragraph.</p><p>Second paragraph.</p><img data-src="/page1.png"><img src="/page2.png"></main>`;
const http = async (request) => {
  requests.push(request);
  return {
    ok: true,
    status: 200,
    body: request.url.includes("/book/")
      ? detail
      : request.url.includes("/chapter/")
        ? chapter
        : catalog,
  };
};
const common = {
  name: "Owned HTML",
  baseUrl: "https://example.org/",
  popularPath: "/popular?page={page}",
  searchPath: "/search?q={query}&page={page}",
  list: {
    item: "section > article.card:nth-child(1)",
    title: "a.title",
    link: "a@href",
    cover: "img@missing|img@data-src",
  },
  detail: { title: "h1", author: "a.author", description: "p.summary", status: "span.status" },
  chapters: {
    item: ".chapters > a:not(.hidden)",
    link: "@href",
    title: "span.name",
    number: "span.num",
    chapter: "span.num",
  },
  headers: { Referer: "https://example.org/" },
};
const fixtures = [];
async function check(name, kind, config, method, args, expected) {
  const runtime = factory({ source: JSON.stringify({ kind, raw: JSON.stringify(config) }) }, http);
  const actual = JSON.parse(JSON.stringify(await runtime.call(method, args)));
  assert.deepEqual(actual, JSON.parse(JSON.stringify(expected)), name);
  fixtures.push({ name, kind, config, method, args, expected: actual });
}
const mangaConfig = { ...common, pages: { image: ".reader img@data-src", pathSuffix: "?images" } };
const ebookConfig = { ...common, content: { body: "main.reader" } };
await check(
  "manga complete CSS list and relative cover",
  "manga",
  mangaConfig,
  "popular",
  [0],
  [{ id: "/book/one", title: "The Book", cover: "https://example.org/cover.png" }],
);
await check(
  "manga search query and page",
  "manga",
  mangaConfig,
  "search",
  ["A + B", 48],
  [{ id: "/book/one", title: "The Book", cover: "https://example.org/cover.png" }],
);
assert(requests.at(-1).url.includes("q=A%20%2B%20B&page=2"));
assert.equal(requests.at(-1).opts.headers.Referer, "https://example.org/");
await check("manga full detail", "manga", mangaConfig, "detail", ["/book/one"], {
  id: "/book/one",
  title: "The Book",
  description: "Owned description",
  author: "Owned author",
  status: "Ongoing",
});
await check(
  "manga chapter selectors and fractional numbers",
  "manga",
  mangaConfig,
  "chapters",
  ["/book/one"],
  [
    { id: "/chapter/one", chapter: "1.5", title: "Chapter One", pages: 0, language: "en" },
    { id: "/chapter/two", chapter: "2", title: "Chapter Two", pages: 0, language: "en" },
  ],
);
await check(
  "manga image attribute fallback",
  "manga",
  mangaConfig,
  "pageUrls",
  ["/chapter/one"],
  ["https://example.org/page1.png", "https://example.org/page2.png"],
);
const bookRuntime = factory(
  { source: JSON.stringify({ kind: "ebook", raw: JSON.stringify(ebookConfig) }) },
  http,
);
const meta = JSON.parse(JSON.stringify(bookRuntime.meta));
const routes = (id) => `source:${encodeURIComponent(meta.id)}:${encodeURIComponent(id)}`;
const listed = {
  id: routes("/book/one"),
  source: "source",
  providerId: meta.id,
  sourceItemId: "/book/one",
  providerName: "Owned HTML",
  title: "The Book",
  authors: [],
  cover: "https://example.org/cover.png",
  description: "",
  genres: [],
};
await check("ebook source identity and CSS list", "ebook", ebookConfig, "popular", [0], [listed]);
await check("ebook detail retains source route", "ebook", ebookConfig, "detail", ["/book/one"], {
  ...listed,
  authors: ["Owned author"],
  description: "Owned description",
  status: "Ongoing",
  cover: undefined,
});
await check(
  "ebook chapter metadata and order",
  "ebook",
  ebookConfig,
  "chapters",
  ["/book/one"],
  [
    { id: "/chapter/one", title: "Chapter One", chapter: "1.5", position: 0 },
    { id: "/chapter/two", title: "Chapter Two", chapter: "2", position: 1 },
  ],
);
await check(
  "ebook content paragraph boundaries",
  "ebook",
  ebookConfig,
  "content",
  ["/chapter/one"],
  { text: "Owned heading\n\nFirst paragraph.\n\nSecond paragraph." },
);
await bookRuntime.call("popular", [0]);
await bookRuntime.call("popular", [1]);
assert(requests.at(-1).url.endsWith("page=2"));
assert.deepEqual(JSON.parse(JSON.stringify(await bookRuntime.call("popular", [999]))), []);
for (const kind of ["manga", "ebook"]) {
  assert.throws(() => factory({ source: JSON.stringify({ kind, raw: "{}" }) }, http));
}
assert.throws(() =>
  factory(
    {
      source: JSON.stringify({
        kind: "ebook",
        raw: JSON.stringify({ ...ebookConfig, baseUrl: "file:///tmp" }),
      }),
    },
    http,
  ),
);
const favicon =
  '<link rel="shortcut icon" href="/small.ico"><link rel="icon" href="/mark.svg"><link rel="apple-touch-icon" href="/touch.png">';
const icon = factory(
  {
    source: JSON.stringify({ kind: "manga", raw: JSON.stringify(mangaConfig), resolveIcon: true }),
  },
  async () => ({ ok: true, status: 200, body: favicon }),
);
await icon.prepare();
assert.equal(icon.meta.icon, "https://example.org/mark.svg");
const fallbackIcon = factory(
  {
    source: JSON.stringify({ kind: "manga", raw: JSON.stringify(mangaConfig), resolveIcon: true }),
  },
  async () => {
    throw new Error("owned no favicon");
  },
);
await fallbackIcon.prepare();
assert.equal(fallbackIcon.meta.icon, "https://example.org/favicon.ico");
await writeFile(
  path.join(root, "ios/Harbor/ReadingHTMLAssets.json"),
  JSON.stringify(
    {
      schema: 1,
      reference: "0834340cec5531650bfe78cd628628702e636987",
      inputs,
      program: { source, sha256: digest(source) },
    },
    null,
    2,
  ) + "\n",
);
await writeFile(
  path.join(root, "ios/HarborTests/Fixtures/reading-html-reference.json"),
  JSON.stringify(
    {
      fixtures,
      documents: { catalog, detail, chapter, favicon },
      faviconCases: 2,
      requestCases: 2,
      paginationCases: 2,
      invalidCases: 3,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  JSON.stringify({
    fixtureCases: fixtures.length,
    requestCases: 2,
    paginationCases: 2,
    invalidCases: 3,
    faviconCases: 2,
    bytes: Buffer.byteLength(source),
    sha256: digest(source),
  }),
);
