import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const index = process.argv.indexOf("--reference");
assert(index >= 0 && process.argv[index + 1]);
const reference = path.resolve(process.argv[index + 1]);
const digest = (text) => createHash("sha256").update(text).digest("hex");
const inputs = {
  "src/lib/ebook/api.ts": "2920911a9a3ea5f361523111eadbcd5cdfe7ebd239d920d36a821002ec050882",
  "src/lib/ebook/browse-filters.ts":
    "bd8219456dc736787ec47e4188a0b0682c99eb6d84c99ec29bc2728e3aa75dad",
  "src/views/ebook.tsx": "5a4c1e436eaa0936c4de72f8253c66a90ae4c71958cef63bbdf5323f3dd763dc",
};
const sources = {};
for (const [name, hash] of Object.entries(inputs)) {
  sources[name] = (await readFile(path.join(reference, name), "utf8")).replaceAll("\r\n", "\n");
  assert.equal(digest(sources[name]), hash, name);
}
function extract(name, names) {
  const tree = ts.createSourceFile(name, sources[name], ts.ScriptTarget.Latest, true);
  assert.equal(tree.parseDiagnostics.length, 0);
  const selected = tree.statements.filter((node) => {
    if (
      ts.isImportDeclaration(node) ||
      ts.isTypeAliasDeclaration(node) ||
      ts.isInterfaceDeclaration(node)
    )
      return false;
    if (!names) return true;
    if (ts.isFunctionDeclaration(node)) return names.includes(node.name?.text);
    return (
      ts.isVariableStatement(node) &&
      node.declarationList.declarations.some((item) => names.includes(item.name.getText(tree)))
    );
  });
  if (names) assert.equal(selected.length, names.length);
  return ts.transpileModule(
    selected.map((node) => node.getText(tree).replace(/^export\s+/, "")).join("\n"),
    {
      fileName: name,
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None },
    },
  ).outputText;
}
const pure =
  extract("src/lib/ebook/api.ts", [
    "EBOOK_CATEGORIES",
    "titleKey",
    "identityTitleKey",
    "authorListsMatch",
    "identityAliases",
    "explicitSourceIdentityMatch",
    "eBooksMatch",
    "dedupeEBooks",
  ]) +
  extract("src/lib/ebook/browse-filters.ts") +
  extract("src/views/ebook.tsx", ["ebookTitleForLanguage"]);
const source = `${pure}
function harborEBookCatalog(text) {
  const input = JSON.parse(text);
  if (input.operation === "definitions") return JSON.stringify({categories:EBOOK_CATEGORIES,genres:EBOOK_FILTER_GENRES});
  if (input.operation === "tag") return JSON.stringify(ebookSourceBrowseTag(input.status,input.sort));
  const grouped = dedupeEBooks(input.books);
  const filtered = applyEBookBrowseFilters(grouped,input.filters);
  const wanted = input.filters.genre || (input.filters.group === "All" ? "" : input.filters.group);
  const genres = !wanted ? [] : input.filters.genre ? [wanted] : [wanted,...(EBOOK_CATEGORIES[input.filters.group]??[])];
  return JSON.stringify(filtered.filter(book => !wanted || genres.some(genre => ebookMatchesGenre(book.genres??[],genre)))
    .map(book=>({id:book.id,title:ebookTitleForLanguage(book,input.titleLanguage),routes:(book.books??[book]).map(item=>item.id)})));
}
`;
const context = vm.createContext({});
vm.runInContext(source, context);
const book = (id, title, extra = {}) => ({
  id,
  title,
  source: "source",
  authors: [],
  genres: [],
  description: "",
  ...extra,
});
const filters = { group: "All", genre: "", status: "any", language: "any", sort: "popular" };
const cases = [];
function check(name, books, expected, options = {}) {
  const input = {
    books,
    filters: { ...filters, ...options.filters },
    titleLanguage: options.titleLanguage ?? "auto",
  };
  const actual = JSON.parse(context.harborEBookCatalog(JSON.stringify(input)));
  assert.deepEqual(
    actual.map((value) => [value.id, value.title, value.routes]),
    expected,
    name,
  );
  cases.push({ name, input, expected: actual });
}
check(
  "all routes survive normalized duplicate titles",
  [book("a", "The Hobbit"), book("b", "Hobbit")],
  [["a", "The Hobbit", ["a", "b"]]],
);
check(
  "different named authors are not merged",
  [book("a", "Home", { authors: ["Author One"] }), book("b", "Home", { authors: ["Writer Two"] })],
  [
    ["a", "Home", ["a"]],
    ["b", "Home", ["b"]],
  ],
);
check(
  "author token order is equivalent",
  [book("a", "Home", { authors: ["Doe John"] }), book("b", "Home", { authors: ["John Doe"] })],
  [["a", "Home", ["a", "b"]]],
);
check(
  "stable source identities merge renamed editions",
  [
    book("a", "Old", { sourceIdentity: { isbn: "123" } }),
    book("b", "New", { sourceIdentity: { isbn: "123" } }),
  ],
  [["a", "Old", ["a", "b"]]],
);
check(
  "trusted Arabic alias prefers readable Latin primary",
  [book("a", "الكتاب", { sourceAliases: ["The Book"] }), book("b", "The Book")],
  [["b", "The Book", ["b", "a"]]],
);
check(
  "unrelated Arabic source remains distinct",
  [book("a", "الكتاب"), book("b", "The Book")],
  [
    ["a", "الكتاب", ["a"]],
    ["b", "The Book", ["b"]],
  ],
);
check(
  "Arabic diacritics and alef normalize",
  [book("a", "إِنْسَان"), book("b", "انسان")],
  [["a", "إِنْسَان", ["a", "b"]]],
);
check(
  "duplicate route uses freshest record",
  [book("a", "Old"), book("a", "New")],
  [["a", "New", ["a"]]],
);
check(
  "nested groups flatten without losing provider",
  [{ ...book("a", "Same"), books: [book("a", "Same"), book("b", "Same")] }, book("c", "Same")],
  [["a", "Same", ["a", "b", "c"]]],
);
const rows = [
  book("a", "Zulu", {
    status: "FINISHED",
    originalLanguage: "jpn",
    genres: ["Science fiction"],
    chapters: 10,
    score: 80,
  }),
  book("b", "Alpha", {
    status: "CURRENT",
    originalLanguage: "ko",
    genres: ["Fantasy"],
    chapters: 30,
    score: 60,
    trendingScore: 99,
  }),
  book("c", "Beta", { status: "on break", originalLanguage: "zh", genres: ["History"] }),
];
check("completed status aliases", rows, [["a", "Zulu", ["a"]]], {
  filters: { status: "completed" },
});
check("ongoing status aliases", rows, [["b", "Alpha", ["b"]]], { filters: { status: "ongoing" } });
check("hiatus status aliases", rows, [["c", "Beta", ["c"]]], { filters: { status: "hiatus" } });
check("original language differs from content language", rows, [["a", "Zulu", ["a"]]], {
  filters: { language: "japanese" },
});
check("genre aliases", rows, [["a", "Zulu", ["a"]]], { filters: { genre: "Sci-fi" } });
check(
  "category group preserves Desktop partial genre matches",
  rows,
  [
    ["a", "Zulu", ["a"]],
    ["c", "Beta", ["c"]],
  ],
  { filters: { group: "Non-fiction" } },
);
check(
  "name ordering",
  rows,
  [
    ["b", "Alpha", ["b"]],
    ["c", "Beta", ["c"]],
    ["a", "Zulu", ["a"]],
  ],
  { filters: { sort: "name" } },
);
check(
  "chapter ordering with missing values",
  rows,
  [
    ["b", "Alpha", ["b"]],
    ["a", "Zulu", ["a"]],
    ["c", "Beta", ["c"]],
  ],
  { filters: { sort: "chapters" } },
);
check(
  "rating ordering",
  rows,
  [
    ["a", "Zulu", ["a"]],
    ["b", "Alpha", ["b"]],
    ["c", "Beta", ["c"]],
  ],
  { filters: { sort: "rating" } },
);
check(
  "trending fallback ordering",
  rows,
  [
    ["b", "Alpha", ["b"]],
    ["a", "Zulu", ["a"]],
    ["c", "Beta", ["c"]],
  ],
  { filters: { sort: "trending" } },
);
check(
  "Arabic display title retains route",
  [book("a", "Book", { altTitle: "本|الكتاب" })],
  [["a", "الكتاب", ["a"]]],
  { titleLanguage: "ar" },
);
check(
  "English display title retains route",
  [book("a", "本", { altTitle: "Book|الكتاب" })],
  [["a", "Book", ["a"]]],
  { titleLanguage: "en" },
);
assert.equal(
  JSON.parse(
    context.harborEBookCatalog(
      JSON.stringify({ operation: "tag", status: "ongoing", sort: "rating" }),
    ),
  ),
  "status:ongoing",
);
assert.equal(
  JSON.parse(
    context.harborEBookCatalog(
      JSON.stringify({ operation: "tag", status: "any", sort: "popular" }),
    ),
  ),
  "sort:popular",
);
const definitions = JSON.parse(
  context.harborEBookCatalog(JSON.stringify({ operation: "definitions" })),
);
assert.equal(definitions.genres.length, 11);
await writeFile(
  path.join(root, "ios/Harbor/EBookCatalogAssets.json"),
  JSON.stringify(
    {
      schema: 1,
      reference: "0834340cec5531650bfe78cd628628702e636987",
      inputs,
      program: { source, sha256: digest(source) },
      definitions,
    },
    null,
    2,
  ) + "\n",
);
await writeFile(
  path.join(root, "ios/HarborTests/Fixtures/ebook-catalog-reference.json"),
  JSON.stringify({ reference: "0834340cec5531650bfe78cd628628702e636987", cases }, null, 2) + "\n",
);
console.log(
  JSON.stringify({
    cases: cases.length,
    tagCases: 2,
    bytes: Buffer.byteLength(source),
    sha256: digest(source),
  }),
);
