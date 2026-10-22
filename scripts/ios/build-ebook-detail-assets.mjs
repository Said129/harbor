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
const file = "src/views/ebook.tsx";
const digest = (value) => createHash("sha256").update(value).digest("hex");
const original = (await readFile(path.join(process.argv[argument + 1], file), "utf8")).replaceAll(
  "\r\n",
  "\n",
);
const inputHash = "5a4c1e436eaa0936c4de72f8253c66a90ae4c71958cef63bbdf5323f3dd763dc";
assert.equal(digest(original), inputHash);
function between(start, end, from = original) {
  const offset = from.indexOf(start);
  assert(offset >= 0, start);
  const finish = from.indexOf(end, offset + start.length);
  assert(finish > offset, end);
  return from.slice(offset + start.length, finish);
}
const tree = ts.createSourceFile(file, original, ts.ScriptTarget.Latest, true);
const number = tree.statements.find(
  (node) => ts.isFunctionDeclaration(node) && node.name?.text === "labelNumber",
);
assert(number);
const grouping = between("const volumeGroups = useMemo(() => {", "\n  }, [chapters]);");
const ordering = between("const ordered = useMemo(() => {", "\n  }, [query, selected, sort]);");
const information =
  "const score =" +
  between(
    "  const score =",
    "\n  const adaptationItems =",
    original.slice(original.indexOf("function EBookInformation(")),
  );
assert(
  grouping.includes("volumeTitle") &&
    ordering.includes("positionDirection") &&
    information.includes("readerRating.toFixed(1)"),
);
const source = ts.transpileModule(
  `${number.getText(tree)}
function groupChapters(chapters) {${grouping}}
function orderedChapters(selected, query, sort) {${ordering}}
function information(ebook, translations) {
 const t=(key, variables={})=>(translations?.[key]??key).replace(/\\{([^{}]+)\\}/g,(match,key)=>String(variables[key]??match));
 ${information}
 return rows;
}
function harborEBookDetail(text) {
 const input=JSON.parse(text);
 if(input.operation==='information')return JSON.stringify(information(input.book,input.translations));
 const groups=groupChapters(input.chapters);
 if(input.operation==='groups')return JSON.stringify(groups);
 const selected=groups.find(group=>group.volume===input.volume)?.chapters??[];
 return JSON.stringify(orderedChapters(selected,input.query??'',input.sort??'oldest'));
}`,
  { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None } },
).outputText;
const context = vm.createContext({});
vm.runInContext(source, context);
const cases = [];
function check(name, input, inspect) {
  const expected = JSON.parse(context.harborEBookDetail(JSON.stringify(input)));
  inspect(expected);
  cases.push({ name, input, expected });
}
const chapter = (id, extra = {}) => ({ id, title: id, ...extra });
check(
  "Arabic and Persian volume digits, titled groups and ungrouped last",
  {
    operation: "groups",
    chapters: [
      chapter("x"),
      chapter("v10", { volume: "Volume ١٠" }),
      chapter("v2", { volume: "Vol ۲", volumeTitle: "Second book" }),
    ],
  },
  (rows) => {
    assert.deepEqual(
      rows.map((row) => [row.volume, row.label, row.number]),
      [
        ["Vol ۲", "Second book", 2],
        ["Volume ١٠", "Volume 10", 10],
        ["", "Chapters", undefined],
      ],
    );
  },
);
check(
  "Provider positions infer descending numbering without altering chapter identity",
  {
    chapters: [
      chapter("c3", { chapter: "3", position: 0 }),
      chapter("c2", { chapter: "2", position: 1 }),
      chapter("c1", { chapter: "1", position: 2 }),
    ],
    volume: "",
  },
  (rows) =>
    assert.deepEqual(
      rows.map((row) => row.id),
      ["c1", "c2", "c3"],
    ),
);
check(
  "Newest reverses stable provider positions and preserves decimal chapters",
  {
    chapters: [
      chapter("c1", { chapter: "1", position: 0 }),
      chapter("c15", { chapter: "1.5", position: 1 }),
      chapter("c2", { chapter: "2", position: 2 }),
    ],
    volume: "",
    sort: "newest",
  },
  (rows) =>
    assert.deepEqual(
      rows.map((row) => row.id),
      ["c2", "c15", "c1"],
    ),
);
check(
  "Missing position falls back to chapter number then natural title order",
  {
    chapters: [
      chapter("Appendix 10"),
      chapter("c10", { chapter: "10" }),
      chapter("c2", { chapter: "2" }),
      chapter("Appendix 2"),
    ],
    volume: "",
  },
  (rows) =>
    assert.deepEqual(
      rows.map((row) => row.id),
      ["c2", "c10", "Appendix 2", "Appendix 10"],
    ),
);
check(
  "Search stays in selected volume and matches chapter number",
  {
    chapters: [
      chapter("one", { volume: "1", chapter: "2", title: "A" }),
      chapter("two", { volume: "2", chapter: "2" }),
    ],
    volume: "1",
    query: " 2 ",
  },
  (rows) =>
    assert.deepEqual(
      rows.map((row) => row.id),
      ["one"],
    ),
);
const book = {
  authors: ["Owned author"],
  genres: ["Fantasy"],
  score: 85,
  publishedAt: "2001-06",
  pages: 300,
  editionCount: 12,
  readerRating: 4.26,
  readerRatingCount: 19,
  shelvedBy: 25,
  people: ["1", "2", "3", "4", "5", "6"],
  places: ["A"],
  periods: ["a", "b", "c", "d", "e"],
  languages: ["en", "es"],
};
check(
  "Desktop ratings scales, edition facts, bounded people and translation counts",
  { operation: "information", book },
  (rows) => {
    const values = Object.fromEntries(rows.map((row) => [row.label, row.value]));
    assert.equal(values.Rating, "8.5 / 10");
    assert.equal(values.Readers, "4.3 / 5 · 19 ratings");
    assert.equal(values.Characters, "1 · 2 · 3 · 4 · 5");
    assert.equal(values.Period, "a · b · c · d");
    assert.equal(values.Translations, "2 languages");
    assert.equal(values["First aired"], "2001-06");
  },
);
check(
  "Missing optional information stays absent and required information remains explicit",
  { operation: "information", book: { authors: [], genres: [], score: 8 } },
  (rows) => {
    assert.equal(rows.length, 5);
    assert.equal(rows[4].value, "8.0 / 10");
    assert.equal(rows[0].value, "Not available");
  },
);
check(
  "Existing interface translations interpolate factual counts",
  {
    operation: "information",
    book,
    translations: {
      "{n} pages": "{n} páginas",
      Readers: "Lectores",
      "{n} ratings": "{n} valoraciones",
    },
  },
  (rows) => {
    assert.equal(rows.find((row) => row.label === "Length").value, "300 páginas");
    assert.equal(rows.find((row) => row.label === "Lectores").value, "4.3 / 5 · 19 valoraciones");
  },
);
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: { [file]: inputHash },
  program: { source, sha256: digest(source) },
};
await writeFile(
  path.join(root, "ios/Harbor/EBookDetailAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
await writeFile(
  path.join(root, "ios/HarborTests/Fixtures/ebook-detail-reference.json"),
  JSON.stringify({ reference: asset.reference, cases }, null, 2) + "\n",
);
console.log(
  JSON.stringify({
    checks: cases.length,
    bytes: Buffer.byteLength(source),
    sha256: asset.program.sha256,
  }),
);
