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
const hash = (value) => createHash("sha256").update(value).digest("hex");
const inputs = {
  "src/views/ebook.tsx": "5a4c1e436eaa0936c4de72f8253c66a90ae4c71958cef63bbdf5323f3dd763dc",
  "src/lib/search.ts": "69c152bcbba9b6a315f18615616a5848448e7ae8b21069e885c5bb97438705ab",
  "src/lib/anilist/browse.ts": "85c5ad426062dc39e388504b54eecf2da9c523954d1ff9c0098792e69cea2d2d",
  "src/lib/providers/anime-catalog-client.ts":
    "adebb312476cad61665c8442add48e9b55bde5a34c0e689eafef3f2465c42b92",
  "src/lib/anilist/client.ts": "b1e96d59bf967d8dea4999a79bb44a8c7726a3aec3bee1e246c0c8adbca28497",
  "src/lib/anilist/config.ts": "9e8053da2c874fd153ce46eca8729900ef6c0321ce7da34b534f50be43035472",
  "src/lib/anilist/errors.ts": "92976b9d24493a42247ed74ea0f20ab8e6b6e1214ee047d2330eb0aeab52bdbf",
};
const sources = {};
for (const [name, digest] of Object.entries(inputs)) {
  sources[name] = (await readFile(path.join(reference, name), "utf8")).replaceAll("\r\n", "\n");
  assert.equal(hash(sources[name]), digest, name);
}
function compile(source) {
  return ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None },
  }).outputText;
}
function extract(name, names) {
  const tree = ts.createSourceFile(name, sources[name], ts.ScriptTarget.Latest, true);
  assert.equal(tree.parseDiagnostics.length, 0);
  const nodes = tree.statements.filter((node) => {
    if (ts.isFunctionDeclaration(node) || ts.isClassDeclaration(node))
      return !names || names.includes(node.name?.text);
    return (
      ts.isVariableStatement(node) &&
      (!names ||
        node.declarationList.declarations.some((value) => names.includes(value.name.getText(tree))))
    );
  });
  if (names) assert.equal(nodes.length, names.length, name);
  return compile(nodes.map((node) => node.getText(tree).replace(/^export\s+/, "")).join("\n"));
}
const view = sources["src/views/ebook.tsx"];
const opening = view.indexOf("const openAdaptation = async (item: EBookAdaptation) => {");
assert(opening > 0);
const open = view.slice(opening, view.indexOf("\n  return (", opening));
const manga = open.slice(open.indexOf('if (item.kind === "manga")'));
const normalize = manga.slice(
  manga.indexOf("const normalizeTitle ="),
  manga.indexOf("const queries ="),
);
const queries = manga.slice(manga.indexOf("const queries ="), manga.indexOf("const results ="));
const choices = manga.slice(
  manga.indexOf("const wanted ="),
  manga.indexOf("setAdaptationStatus(null);"),
);
const direct = open.slice(
  open.indexOf('if (item.kind === "anime" && item.anilistId)'),
  open.indexOf('if (item.kind === "anime")'),
);
const anime =
  'if (item.kind === "anime") {' +
  open.slice(open.indexOf("const titleKey ="), open.indexOf('if (item.kind === "manga")'));
assert(
  queries.includes("slice(0, 8)") && choices.includes("slice(0, 3)") && anime.includes("openMeta("),
);
const pure = compile(`function mangaQueries(item,ebook){${normalize}${queries}return queries;}
function mangaChoices(queries,results){${normalize}${choices}return candidates;}
function animeRoute(item,matches=[]){let result=null;const openMeta=value=>{result=value;};(()=>{${direct}${anime}})();return result;}`);
const client =
  extract("src/lib/anilist/config.ts", ["ANILIST_GRAPHQL_URL"]) +
  extract("src/lib/anilist/errors.ts") +
  extract("src/lib/anilist/client.ts");
const anilist = extract("src/lib/anilist/browse.ts", ["SEARCH_QUERY", "anilistAnimeSearch"]);
const catalog = extract("src/lib/providers/anime-catalog-client.ts", [
  "ANIME_CATALOG_BASE",
  "ANIME_CATALOG_FALLBACK",
  "catalogRetryDelay",
  "createAnimeCatalogClient",
]);
const search = extract("src/lib/search.ts", [
  "jikanAnimeSearch",
  "kitsuAnimeSearch",
  "withSearchTimeout",
  "searchAnime",
]);
const source = `var plugin=(()=>{
  const getSession=()=>null;
  const AbortSignal={timeout(ms){const controller=new AbortController();setTimeout(()=>controller.abort(),ms);return controller.signal;}};
  async function safeFetch(url,opts={}){
    const value=await new Promise((resolve,reject)=>{
      const signal=opts.signal,abort=()=>reject(new Error("Adaptation request aborted"));
      if(signal?.aborted){abort();return;}
      signal?.addEventListener("abort",abort,{once:true});
      harbor.http(String(url),{method:opts.method??"GET",headers:opts.headers??{},body:opts.body,responseType:"text",timeoutMs:12000})
        .then(value=>{signal?.removeEventListener("abort",abort);resolve(value);},error=>{signal?.removeEventListener("abort",abort);reject(error);});
    });
    return {ok:value.ok===true,status:value.status,headers:{get(name){return Object.entries(value.headers??{}).find(([key])=>key.toLowerCase()===name.toLowerCase())?.[1]??null;}},text:async()=>String(value.body??""),json:async()=>JSON.parse(String(value.body??""))};
  }
  ${client}
  const anilistAnimeSearch=(()=>{${anilist}return anilistAnimeSearch;})();
  const animeCatalogRequest=(()=>{${catalog}return createAnimeCatalogClient({fetch:safeFetch,fallbackFetch:safeFetch});})();
  ${search}
  ${pure}
  return {id:"harbor-book-adaptations",name:"Harbor Adaptations",content(input){
    switch(input.operation){
      case "manga-queries":return mangaQueries(input.item,input.book);
      case "manga-choices":return mangaChoices(input.queries,input.results);
      case "anime-route":return animeRoute(input.item,input.matches);
      case "anime-search":return searchAnime(input.query,input.limit??8);
      default:throw new Error("Unknown adaptation operation");
    }
  }};
})();`;
new vm.Script(source);
const requests = [];
const anilistRows = [
  {
    id: 10,
    idMal: 20,
    title: { english: "Owned Anime" },
    seasonYear: 2020,
    averageScore: 80,
    coverImage: { large: "https://example.org/a.png" },
  },
];
const jikanRows = [
  { mal_id: 20, title: "Duplicate MAL" },
  { mal_id: 30, title_english: "Jikan Owned", score: 7 },
];
const kitsuRows = [
  { id: "40", attributes: { titles: { en: "owned anime" } } },
  {
    id: "41",
    attributes: { canonicalTitle: "Kitsu Owned", subtype: "TV", startDate: "2021-01-01" },
  },
];
const context = vm.createContext({
  URL,
  URLSearchParams,
  AbortController,
  clearTimeout,
  setTimeout: (fn, ms) => {
    const timer = setTimeout(fn, ms);
    timer.unref();
    return timer;
  },
  harbor: {
    async http(url, opts) {
      requests.push({ url, opts });
      const body = url.includes("graphql.anilist")
        ? { data: { Page: { media: anilistRows } } }
        : url.includes("kitsu.io")
          ? { data: kitsuRows }
          : { data: jikanRows };
      return { ok: true, status: 200, headers: {}, body: JSON.stringify(body) };
    },
  },
});
vm.runInContext(source, context);
const cases = [];
async function check(name, input, expected) {
  const actual = JSON.parse(JSON.stringify(await context.plugin.content(input)));
  assert.deepEqual(actual, expected, name);
  cases.push({ name, input, expected: actual });
}
const item = {
  kind: "manga",
  title: "Owned Manga",
  altTitles: [
    "OWNED MANGA",
    "Ｏｗｎｅｄ Ｍａｎｇａ",
    "Alias",
    "第二",
    "Third",
    "Fourth",
    "Fifth",
    "Sixth",
    "Seventh",
  ],
};
const book = { title: "Owned Novel", altTitle: "Alias|الثاني", seriesTitle: "Series" };
await check(
  "Eight normalized distinct manga queries preserve original order",
  { operation: "manga-queries", item, book },
  ["Owned Manga", "Alias", "第二", "Third", "Fourth", "Fifth", "Sixth", "Seventh"],
);
await check(
  "Exact manga matches prefer aliases and remove duplicate routes",
  {
    operation: "manga-choices",
    queries: ["Owned Manga", "Alias"],
    results: [
      [
        { id: "c", title: "Other" },
        { id: "a", title: "Owned Manga" },
      ],
      [
        { id: "b", title: "Different", altTitle: "Ａｌｉａｓ" },
        { id: "a", title: "Owned Manga" },
      ],
    ],
  },
  [
    { id: "a", title: "Owned Manga" },
    { id: "b", title: "Different", altTitle: "Ａｌｉａｓ" },
  ],
);
await check(
  "No exact manga match keeps at most three actual source routes",
  {
    operation: "manga-choices",
    queries: ["Absent"],
    results: [
      [
        { id: "a", title: "A" },
        { id: "b", title: "B" },
        { id: "c", title: "C" },
        { id: "d", title: "D" },
      ],
    ],
  },
  [
    { id: "a", title: "A" },
    { id: "b", title: "B" },
    { id: "c", title: "C" },
  ],
);
await check(
  "Known AniList adaptation opens its exact anime identity",
  {
    operation: "anime-route",
    item: {
      kind: "anime",
      title: "Owned",
      anilistId: 42,
      poster: "https://example.org/a.png",
      year: 2020,
      format: "TV",
    },
  },
  {
    id: "anilist:42",
    type: "anime",
    name: "Owned",
    poster: "https://example.org/a.png",
    releaseInfo: "2020",
    animeFormat: "TV",
  },
);
const matches = [
  { name: "Other", malId: 1, score: 0 },
  { name: "OWNED-ANIME", malId: 2, kitsuId: 3, score: 8, format: "MOVIE" },
];
await check(
  "Anime exact normalized name takes precedence over first result",
  {
    operation: "anime-route",
    item: { kind: "anime", title: "Owned Anime", poster: "https://example.org/fallback.png" },
    matches,
  },
  {
    id: "kitsu:3",
    type: "anime",
    name: "OWNED-ANIME",
    poster: "https://example.org/fallback.png",
    background: "https://example.org/fallback.png",
    imdbRating: "8.0",
    animeFormat: "MOVIE",
  },
);
await check(
  "No exact anime title keeps original first real result",
  {
    operation: "anime-route",
    item: { kind: "anime", title: "Absent" },
    matches: [{ name: "First", malId: 1, score: 0 }],
  },
  { id: "mal:1", type: "anime", name: "First" },
);
await check(
  "No anime match does not manufacture a playable identity",
  { operation: "anime-route", item: { kind: "anime", title: "Absent" }, matches: [] },
  null,
);
const hits = await context.plugin.content({ operation: "anime-search", query: "Owned", limit: 8 });
assert.deepEqual(
  JSON.parse(JSON.stringify(hits)).map((row) => [row.name, row.malId, row.kitsuId ?? null]),
  [
    ["Owned Anime", 20, null],
    ["Jikan Owned", 30, null],
    ["Kitsu Owned", 0, 41],
  ],
);
assert.equal(requests.length, 3);
assert(requests.some((row) => row.url.startsWith("https://api.tenrai.org/v1/anime?")));
assert.equal(
  requests.find((row) => row.url.includes("graphql.anilist")).opts.headers.Authorization,
  undefined,
);
await writeFile(
  path.join(root, "ios/Harbor/EBookAdaptationAssets.json"),
  JSON.stringify(
    {
      schema: 1,
      reference: "0834340cec5531650bfe78cd628628702e636987",
      inputs,
      program: { source, sha256: hash(source) },
    },
    null,
    2,
  ) + "\n",
);
await writeFile(
  path.join(root, "ios/HarborTests/Fixtures/ebook-adaptation-reference.json"),
  JSON.stringify(
    {
      cases,
      anilistRows,
      jikanRows,
      kitsuRows,
      additionalChecks: [
        "actual-three-provider-search-and-deduplication",
        "original-public-provider-endpoint",
        "anonymous-anilist-query",
      ],
    },
    null,
    2,
  ) + "\n",
);
console.log(
  JSON.stringify({
    cases: cases.length,
    additionalChecks: 3,
    bytes: Buffer.byteLength(source),
    sha256: hash(source),
  }),
);
