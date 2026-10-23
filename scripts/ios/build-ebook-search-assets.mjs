import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

const argument = process.argv.indexOf("--reference");
assert(argument >= 0 && process.argv[argument + 1]);
const file = "src/views/ebook/harbor-reader.tsx";
const bytes = await readFile(path.join(process.argv[argument + 1], file));
const hash = (value) => createHash("sha256").update(value).digest("hex");
const inputHash = "167f062f191238e2bbf016e5902aefc4a47b49a1dd11ce4c5f65608be28871f8";
assert.equal(hash(bytes), inputHash);
const original = bytes.toString("utf8").replaceAll("\r\n", "\n");
const tree = ts.createSourceFile(file, original, ts.ScriptTarget.Latest, true);
const definitions = ["marks", "stripMarks"]
  .map((name) => {
    const node = tree.statements.find(
      (node) =>
        ts.isVariableStatement(node) &&
        node.declarationList.declarations.some((item) => item.name.getText(tree) === name),
    );
    assert(node);
    return node.getText(tree);
  })
  .join("\n");
function between(first, last) {
  const start = original.indexOf(first);
  assert(start >= 0);
  const end = original.indexOf(last, start + first.length);
  assert(end > start);
  return original.slice(start + first.length, end);
}
const results = between("  const results = useMemo(() => {", "\n  }, [paragraphs, query]);");
const shown = between(
  "  const shownResults =",
  "\n\n  useEffect(() => setShowFutureResults(false)",
);
const source = ts.transpileModule(
  `${definitions}
function harborEBookSearch(text) {
 const input=JSON.parse(text),paragraphs=input.paragraphs,query=input.query,current=input.current,showFutureResults=input.showFutureResults;
 const results=(()=>{${results}})();
 const shownResults=${shown}
 return JSON.stringify({shown:shownResults,hidden:hiddenResults,total:results.length});
}`,
  { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None } },
).outputText;
const context = vm.createContext({});
vm.runInContext(source, context, { timeout: 1000 });
const cases = [];
function check(name, input, inspect) {
  const expected = JSON.parse(context.harborEBookSearch(JSON.stringify(input)));
  inspect(expected);
  cases.push({ name, input, expected });
}
const input = (paragraphs, query, current = 0, showFutureResults = false) => ({
  paragraphs,
  query,
  current,
  showFutureResults,
});
check("empty query", input(["Harbor"], " \t "), (r) => assert.equal(r.total, 0));
check("Latin decomposition and case", input(["CAFÉ près du río"], " cafe "), (r) =>
  assert.equal(r.shown[0].index, 0),
);
check("Arabic marks", input(["هٰذَا كِتَابٌ جَمِيلٌ"], "كتاب"), (r) => assert.equal(r.total, 1));
check(
  "future matches stay sealed",
  input(["Harbor before", "Harbor now", "Harbor ahead", "Harbor farther"], "harbor", 1),
  (r) => {
    assert.equal(r.shown.length, 2);
    assert.equal(r.hidden, 2);
  },
);
check(
  "explicit future reveal",
  input(["Harbor before", "Harbor now", "Harbor ahead"], "harbor", 0, true),
  (r) => {
    assert.equal(r.shown.length, 3);
    assert.equal(r.hidden, 0);
  },
);
check("literal punctuation is not regex", input(["A.*B", "Another B", "a*b"], ".*"), (r) =>
  assert.deepEqual(
    r.shown.map((x) => x.index),
    [0],
  ),
);
check(
  "substring search matches original",
  input(["Harbor ship", "warship", "boat"], "ship", 2),
  (r) => assert.equal(r.total, 2),
);
check("emoji and astral characters", input(["Book 😀𐐀", "Another book"], "😀𐐀"), (r) =>
  assert.equal(r.total, 1),
);
check(
  "no arbitrary result cap",
  input(
    Array.from({ length: 240 }, (_, i) => `Harbor ${i}`),
    "harbor",
    239,
  ),
  (r) => assert.equal(r.shown.length, 240),
);
check("no matches", input(["Book", "Chapter"], "missing"), (r) => assert.equal(r.total, 0));
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: { [file]: inputHash },
  program: { source, sha256: hash(source) },
};
await writeFile("ios/Harbor/EBookSearchAssets.json", JSON.stringify(asset, null, 2) + "\n");
await writeFile(
  "ios/HarborTests/Fixtures/ebook-search-reference.json",
  JSON.stringify({ reference: asset.reference, inputs: asset.inputs, cases }, null, 2) + "\n",
);
console.log(
  JSON.stringify({ originalSearchCases: cases.length, programSha256: asset.program.sha256 }),
);
