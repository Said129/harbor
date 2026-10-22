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
  "src/lib/ebook/api.ts": "2920911a9a3ea5f361523111eadbcd5cdfe7ebd239d920d36a821002ec050882",
  "src/lib/anilist/client.ts": "b1e96d59bf967d8dea4999a79bb44a8c7726a3aec3bee1e246c0c8adbca28497",
  "src/lib/anilist/config.ts": "9e8053da2c874fd153ce46eca8729900ef6c0321ce7da34b534f50be43035472",
  "src/lib/anilist/errors.ts": "92976b9d24493a42247ed74ea0f20ab8e6b6e1214ee047d2330eb0aeab52bdbf",
  "src/lib/anilist/relations.ts":
    "fbd0d89c28f0a975e7176199cb42b64314146a55b1f5eda898125eabc7d7899c",
  "src/views/ebook.tsx": "5a4c1e436eaa0936c4de72f8253c66a90ae4c71958cef63bbdf5323f3dd763dc",
};
const sources = {};
for (const [name, digest] of Object.entries(inputs)) {
  sources[name] = (await readFile(path.join(reference, name), "utf8")).replaceAll("\r\n", "\n");
  assert.equal(hash(sources[name]), digest, name);
}
function extract(name, names) {
  const tree = ts.createSourceFile(name, sources[name], ts.ScriptTarget.Latest, true);
  assert.equal(tree.parseDiagnostics.length, 0);
  const selected = tree.statements.filter((node) => {
    if (
      ts.isImportDeclaration(node) ||
      ts.isExportDeclaration(node) ||
      ts.isTypeAliasDeclaration(node) ||
      ts.isInterfaceDeclaration(node)
    )
      return false;
    if (!names) return true;
    if (ts.isFunctionDeclaration(node) || ts.isClassDeclaration(node))
      return names.includes(node.name?.text);
    return (
      ts.isVariableStatement(node) &&
      node.declarationList.declarations.some((item) => names.includes(item.name.getText(tree)))
    );
  });
  if (names) assert.equal(selected.length, names.length);
  const assertAnonymous = (node) => {
    if (ts.isCallExpression(node) && node.expression.getText(tree) === "anilistRequest") {
      assert.equal(node.arguments.length, 4);
      assert.equal(node.arguments[3].kind, ts.SyntaxKind.TrueKeyword);
    }
    ts.forEachChild(node, assertAnonymous);
  };
  selected.forEach(assertAnonymous);
  return ts.transpileModule(
    selected.map((node) => node.getText(tree).replace(/^export\s+/, "")).join("\n"),
    {
      fileName: name,
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None },
    },
  ).outputText;
}
const client =
  extract("src/lib/anilist/config.ts", ["ANILIST_GRAPHQL_URL"]) +
  extract("src/lib/anilist/errors.ts") +
  extract("src/lib/anilist/client.ts");
const relations = extract("src/lib/anilist/relations.ts", [
  "RELATIONS_QUERY",
  "edgeCache",
  "fetchEdges",
  "fmtDate",
  "toNode",
  "MAX_RELATIONS",
  "animeRelations",
]);
const api = extract("src/lib/ebook/api.ts");
const view = sources["src/views/ebook.tsx"];
const effect = view.slice(
  view.indexOf(
    'const existing = (ebook.books ?? [ebook]).filter((book) => book.source === "source");',
  ),
);
assert(effect.startsWith("const existing ="));
const queries = effect.slice(
  effect.indexOf("const queries ="),
  effect.indexOf("const normalizedAuthors ="),
);
const authors = effect.slice(
  effect.indexOf("const normalizedAuthors ="),
  effect.indexOf("void Promise.all("),
);
const promising = effect.slice(
  effect.indexOf("const promising = uniqueCandidates"),
  effect.indexOf("const hydrated ="),
);
const matches = effect.slice(
  effect.indexOf("const matches = dedupeEBooks"),
  effect.indexOf("setSourceOptions(uniqueMatches);"),
);
assert(
  queries.includes("sourceAliases") &&
    promising.includes("slice(0, 32)") &&
    matches.includes("const uniqueMatches"),
);
const resolver = ts.transpileModule(
  `function resolutionQueries(ebook){${queries}return [...new Set(queries)].slice(0,6);}
function promisingSources(ebook,uniqueCandidates,existing){${authors}${promising}return promising;}
function matchedSources(ebook,resolvedCandidates){${matches}return uniqueMatches;}`,
  {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None },
  },
).outputText;
const source = `var plugin=(()=>{
  let engine;
  function create(options={}){
  const cache=new Map(Object.entries(options.cache??{}));
  const localStorage={getItem:key=>cache.get(key)??null,setItem:(key,value)=>cache.set(String(key),String(value)),removeItem:key=>cache.delete(key),key:index=>[...cache.keys()][index]??null,get length(){return cache.size;}};
  const window={setTimeout,clearTimeout,dispatchEvent(){}};
  const getUiLanguage=()=>options.language??"en";
  const getSession=()=>null;
  const setItemWithRecovery=(key,value)=>{localStorage.setItem(key,value);return true;};
  const AbortSignal={timeout(ms){const controller=new AbortController();setTimeout(()=>controller.abort(),ms);return controller.signal;}};
  async function safeFetch(url,opts={}){
    const signal=opts.signal;
    const value=await new Promise((resolve,reject)=>{
      const abort=()=>reject(new Error("Book metadata request aborted"));
      if(signal?.aborted){abort();return;}
      signal?.addEventListener("abort",abort,{once:true});
      harbor.http(String(url),{method:opts.method??"GET",headers:opts.headers??{},body:opts.body,responseType:"text",timeoutMs:15000})
        .then(value=>{signal?.removeEventListener("abort",abort);resolve(value);},error=>{signal?.removeEventListener("abort",abort);reject(error);});
    });
    return {ok:value.ok===true,status:value.status,headers:{get(name){return Object.entries(value.headers??{}).find(([key])=>key.toLowerCase()===name.toLowerCase())?.[1]??null;}},text:async()=>String(value.body??""),json:async()=>JSON.parse(String(value.body??""))};
  }
  ${client}
  const animeRelations=(()=>{${relations}\nreturn animeRelations;})();
  ${api}
  ${resolver}
  if(options.googleKey)localStorage.setItem(GOOGLE_BOOKS_KEY,options.googleKey);
  function snapshot(){flushMetadataCache();pruneOpenLibraryCache();return Object.fromEntries([...cache].filter(([key])=>key===EBOOK_METADATA_CACHE_KEY||key.startsWith(OPEN_LIBRARY_PREFIX)));}
  return {id:"harbor-book-metadata",name:"Harbor Books",async content(input){
    switch(input.operation){
      case "enrich":{const publish=metadata=>{if(input.requestID)void harbor.http("harbor://book-metadata-progress/"+input.requestID,{method:"POST",responseType:"text",body:JSON.stringify(dedupeEBooks(mergeEBookMetadata(input.books,metadata)))}).catch(()=>{});};const metadata=await fetchEBookMetadata(input.books,publish);return dedupeEBooks(mergeEBookMetadata(input.books,metadata));}
      case "cached":return dedupeEBooks(mergeEBookMetadata(input.books,cachedMetadata(input.books)));
      case "merge":return dedupeEBooks(mergeEBookMetadata(input.books,input.metadata??[]));
      case "map":return input.kind==="anilist"?mapEBook(input.raw):input.kind==="googlebooks"?mapGoogleBook(input.raw):input.kind==="wikidata"?mapWikidata(input.raw,input.summary):mapOpenLibrary(input.raw);
      case "browse":return browseEBooks(input.sort??"POPULARITY_DESC",input.page??1,input.query);
      case "popular":return browsePopularEBooks();
      case "new":return browseNewReleases();
      case "search":return searchEBooks(input.query,input.category);
      case "category":return browseEBookCategory(input.category);
      case "detail":return ebookDetail(input.id);
      case "recommendations":return recommendedEBooks(input.book);
      case "collections":return ebookCollections(input.books??[input.book]);
      case "collection":return ebookCollection(input.book);
      case "source-queries":return resolutionQueries(input.book);
      case "source-promising":return promisingSources(input.book,input.candidates,input.existing??[]);
      case "source-matches":return matchedSources(input.book,input.candidates);
      case "attach":return attachEBookCollectionSources(input.books,input.sources);
      case "adaptations":return ebookAdaptations(input.book);
      case "validate-key":await validateGoogleBooksApiKey(input.key);return {ok:true};
      case "snapshot":return snapshot();
      default:throw new Error("Unknown book metadata operation");
    }
  }};
  }
  return {id:"harbor-book-metadata",name:"Harbor Books",async content(input){
    if(input.operation==="configure"){engine=create(input.options??{});return {configured:true};}
    if(!engine)throw new Error("Book metadata has not been configured");
    return engine.content(input);
  }};
})();`;
new vm.Script(source);
const fixtureCases = [];
const requests = [];
async function runtime(options = {}) {
  const context = vm.createContext({
    URL,
    URLSearchParams,
    AbortController,
    Event,
    Promise,
    clearTimeout,
    setTimeout: (fn, ms) => {
      const timer = setTimeout(fn, ms);
      timer.unref();
      return timer;
    },
    harbor: {
      async http(url, opts) {
        requests.push({ url, opts });
        return {
          ok: true,
          status: 200,
          headers: {},
          body: JSON.stringify(
            url.includes("graphql.anilist")
              ? { data: { Page: { media: [] } } }
              : url.includes("www.googleapis.com/books")
                ? new URL(url).pathname.includes("/volumes/")
                  ? google
                  : { items: [google] }
                : { items: [], docs: [], entities: {}, results: { bindings: [] } },
          ),
        };
      },
    },
  });
  vm.runInContext(source, context);
  assert.equal(context.config, undefined);
  assert.deepEqual(
    JSON.parse(
      JSON.stringify(
        await context.plugin.content({
          operation: "configure",
          options: { language: "en", ...options },
        }),
      ),
    ),
    { configured: true },
  );
  return context.plugin;
}
const program = await runtime();
async function check(name, input, expected) {
  const actual = JSON.parse(JSON.stringify(await program.content(input)));
  assert.deepEqual(actual, expected, name);
  fixtureCases.push({ name, input, expected: actual });
}
const anilist = {
  id: 42,
  title: { english: "Owned Novel", romaji: "Owned Romaji", native: "所有小説" },
  coverImage: {
    extraLarge: "https://example.org/large.jpg",
    large: "https://example.org/small.jpg",
  },
  bannerImage: null,
  description: "<p>Owned description<br>Second line</p>",
  startDate: { year: 2020, month: 2, day: 3 },
  status: "FINISHED",
  genres: ["Fantasy"],
  chapters: 20,
  volumes: 2,
  averageScore: 85,
  countryOfOrigin: "JP",
  siteUrl: "https://anilist.co/manga/42",
  staff: {
    edges: [
      { role: "Story", node: { name: { full: "Owned Writer" } } },
      { role: "Art", node: { name: { full: "Owned Artist" } } },
    ],
  },
};
await check(
  "AniList novel identity authors dates and content",
  { operation: "map", kind: "anilist", raw: anilist },
  {
    id: "anilist:42",
    source: "anilist",
    anilistId: 42,
    title: "Owned Novel",
    altTitle: "Owned Romaji",
    authors: ["Owned Writer"],
    cover: "https://example.org/large.jpg",
    description: "Owned description\nSecond line",
    year: 2020,
    publishedAt: "2020-02-03",
    status: "finished",
    originalLanguage: "JP",
    genres: ["Fantasy"],
    chapters: 20,
    volumes: 2,
    score: 85,
    siteUrl: "https://anilist.co/manga/42",
  },
);
const google = {
  id: "owned-google",
  volumeInfo: {
    title: "Owned Book",
    authors: ["Owned Writer"],
    publishedDate: "1999-04-01",
    description: "<p>Owned</p>",
    industryIdentifiers: [
      { type: "ISBN_10", identifier: "0123456789" },
      { type: "ISBN_13", identifier: "9780123456789" },
    ],
    categories: ["Fiction"],
    averageRating: 4.5,
    imageLinks: {
      thumbnail: "http://example.org/thumb.jpg",
      large: "http://example.org/large.jpg",
    },
    infoLink: "https://books.google.com/owned",
  },
};
await check(
  "Google Books chooses ISBN13 and largest HTTPS cover",
  { operation: "map", kind: "googlebooks", raw: google },
  {
    id: "googlebooks:owned-google",
    source: "googlebooks",
    googleBooksId: "owned-google",
    isbn: "9780123456789",
    title: "Owned Book",
    authors: ["Owned Writer"],
    cover: "https://example.org/large.jpg",
    description: "Owned",
    year: 1999,
    publishedAt: "1999-04-01",
    genres: ["Fiction"],
    score: 90,
    siteUrl: "https://books.google.com/owned",
  },
);
const open = {
  key: "/works/OWNED",
  title: "Owned library book",
  author_name: ["Writer"],
  first_sentence: ["Opening."],
  first_publish_year: 1900,
  subject: ["Fantasy"],
  number_of_pages_median: 200,
  edition_count: 4,
  ratings_average: 4.2,
  ratings_count: 12,
  want_to_read_count: 50,
  subject_people: ["Person"],
  subject_places: ["Place"],
  subject_times: ["Time"],
  language: ["eng", "spa"],
  ia: ["copy1", "copy2"],
  cover_i: 12,
  isbn: ["123"],
};
await check(
  "Open Library preserves edition and reading metadata",
  { operation: "map", kind: "openlibrary", raw: open },
  {
    id: "openlibrary:OWNED",
    source: "openlibrary",
    openLibraryId: "OWNED",
    isbn: "123",
    title: "Owned library book",
    authors: ["Writer"],
    cover: "https://covers.openlibrary.org/b/id/12-L.jpg",
    description: "Opening.",
    year: 1900,
    publishedAt: "1900",
    genres: ["Fantasy"],
    pages: 200,
    editionCount: 4,
    readerRating: 4.2,
    readerRatingCount: 12,
    shelvedBy: 50,
    people: ["Person"],
    places: ["Place"],
    periods: ["Time"],
    languages: ["eng", "spa"],
    archiveCopies: 2,
    siteUrl: "https://openlibrary.org/works/OWNED",
  },
);
const base = {
  id: "source:owned",
  source: "source",
  providerId: "plugin:owned",
  sourceItemId: "one",
  title: "Owned Book",
  authors: ["Owned Writer"],
  genres: [],
  description: "Source description",
  chapters: 12,
  volumes: 1,
};
const rawMeta = JSON.parse(
  JSON.stringify(await program.content({ operation: "map", kind: "googlebooks", raw: google })),
);
const merged = await program.content({ operation: "merge", books: [base], metadata: [rawMeta] });
assert.equal(merged[0].id, base.id);
assert.equal(merged[0].chapters, 12);
assert.equal(merged[0].isbn, "9780123456789");
fixtureCases.push({
  name: "Verified metadata enriches without losing readable source",
  input: { operation: "merge", books: [base], metadata: [rawMeta] },
  expected: JSON.parse(JSON.stringify(merged)),
});
const rejected = await program.content({
  operation: "merge",
  books: [{ ...base, authors: ["Different Writer"] }],
  metadata: [rawMeta],
});
assert.equal(rejected[0].googleBooksId, undefined);
fixtureCases.push({
  name: "Unrelated authors cannot lend another book's metadata",
  input: {
    operation: "merge",
    books: [{ ...base, authors: ["Different Writer"] }],
    metadata: [rawMeta],
  },
  expected: JSON.parse(JSON.stringify(rejected)),
});
await program.content({ operation: "validate-key", key: "owned-test-key" });
assert(requests.some(({ url }) => url.includes("key=owned-test-key")));
const snapshot = await program.content({ operation: "snapshot" });
assert(!JSON.stringify(snapshot).includes("owned-test-key"));
await program.content({ operation: "browse", sort: "SCORE_DESC", page: 2 });
const request = requests.find(({ url }) => url.includes("graphql.anilist"));
assert(request);
assert.equal(request.opts.headers.Authorization, undefined);
assert.equal(JSON.parse(request.opts.body).variables.page, 2);
const arabic = await runtime({ language: "ar" });
const localized = await arabic.content({
  operation: "map",
  kind: "anilist",
  raw: { ...anilist, synonyms: ["الرواية"] },
});
assert.equal(localized.title, "الرواية");
const keepAlive = setTimeout(() => {}, 10000);
try {
  const secret = await runtime({ googleKey: "owned-secret-key" });
  const enriched = await secret.content({
    operation: "enrich",
    books: [base],
    requestID: "owned-request",
  });
  assert.equal(enriched[0].googleBooksId, google.id);
  assert.equal(enriched[0].id, base.id);
  assert(
    requests.some(
      (request) =>
        request.url === "harbor://book-metadata-progress/owned-request" &&
        JSON.parse(request.opts.body)[0].id === base.id,
    ),
  );
  const saved = await secret.content({ operation: "snapshot" });
  assert(!JSON.stringify(saved).includes("owned-secret-key"));
  const previous = requests.length;
  await secret.content({ operation: "enrich", books: [base] });
  assert.equal(requests.length, previous);
} finally {
  clearTimeout(keepAlive);
}
const queryTitles = await program.content({
  operation: "source-queries",
  book: { ...base, sourceAliases: ["Alias", "Alias", "Two", "Three", "Four", "Five", "Six"] },
});
assert.deepEqual(JSON.parse(JSON.stringify(queryTitles)), [
  "Owned Book",
  "Alias",
  "Two",
  "Three",
  "Four",
  "Five",
]);
const linked = await program.content({ operation: "attach", books: [rawMeta], sources: [base] });
assert.equal(linked[0].id, base.id);
await writeFile(
  path.join(root, "ios/Harbor/EBookMetadataAssets.json"),
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
  path.join(root, "ios/HarborTests/Fixtures/ebook-metadata-reference.json"),
  JSON.stringify(
    {
      cases: fixtureCases,
      anilist,
      google,
      open,
      base,
      additionalChecks: [
        "key-validation-request",
        "anonymous-graphql-request-and-pagination",
        "Arabic-original-synonym",
        "actual-network-enrichment-and-verified-source",
        "incremental-native-progress",
        "configured-key-excluded-from-cache",
        "fresh-result-does-not-repeat-network",
        "exact-six-source-queries",
        "metadata-links-to-readable-route",
      ],
    },
    null,
    2,
  ) + "\n",
);
console.log(
  JSON.stringify({
    cases: fixtureCases.length,
    additionalChecks: 9,
    bytes: Buffer.byteLength(source),
    sha256: hash(source),
  }),
);
