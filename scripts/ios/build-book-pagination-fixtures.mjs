import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

const argument = process.argv.indexOf("--reference");
assert(argument >= 0 && process.argv[argument + 1]);
const reference = process.argv[argument + 1];
const files = {
  "src/lib/ebook/book-pages.ts": "00d3e202e06de65fb0fce9e4b0e4ebccb508e49c551ce7b65f4517ce8d3200fb",
  "src/views/ebook/harbor-reader.tsx":
    "167f062f191238e2bbf016e5902aefc4a47b49a1dd11ce4c5f65608be28871f8",
};
const values = {};
for (const [file, expected] of Object.entries(files)) {
  const bytes = await readFile(path.join(reference, file));
  assert.equal(createHash("sha256").update(bytes).digest("hex"), expected);
  values[file] = bytes.toString("utf8").replaceAll("\r\n", "\n");
}
const source = values["src/lib/ebook/book-pages.ts"],
  reader = values["src/views/ebook/harbor-reader.tsx"];
const tree = ts.createSourceFile("book-pages.ts", source, ts.ScriptTarget.Latest, true);
const functions = ["abortError", "throwIfAborted", "wrap"]
  .map((name) => {
    const found = tree.statements.find(
      (node) => ts.isFunctionDeclaration(node) && node.name?.text === name,
    );
    assert(found);
    return found.getText(tree);
  })
  .join("\n");
const slice = (start, end) => {
  const first = source.indexOf(start);
  assert(first >= 0);
  const last = source.indexOf(end, first);
  assert(last > first);
  return source.slice(first, last);
};
const constants = ["WIDTH", "HEIGHT", "PAD_X", "PAD_Y"]
  .map((name) => {
    const found = source.match(new RegExp(`const ${name} = \\d+;`));
    assert(found);
    return found[0];
  })
  .join("\n");
const metrics = slice("  const bodySize =", "  try {");
const rows = slice("  const paragraphs =", "  const blobs:");
const resume = reader.slice(
  reader.indexOf("const pageForParagraph ="),
  reader.indexOf("\nfunction TranslationSpinner"),
);
const paper = reader.slice(reader.indexOf("const paper ="), reader.indexOf("\nconst inks ="));
const code = ts.transpileModule(
  `${constants}\n${functions}\n${resume}\n${paper}\nfunction layout(input){
const options={fontSize:input.fontSize,lineHeight:input.lineHeight,content:{text:input.text}};
const context={measureText:value=>({width:value.length*input.measureFactor})},signal={aborted:false};
${metrics}\n${rows}\nconst pages=[];for(let start=0;start<rows.length;start+=rowsPerPage)pages.push(rows.slice(start,start+rowsPerPage));
return {bodySize,rowHeight,rowsPerPage,pages};}
globalThis.reference={layout,pageForParagraph,paper};`,
  { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } },
).outputText;
const context = vm.createContext({ DOMException });
new vm.Script(code).runInContext(context, { timeout: 1000 });
const samples = [
  ["paragraphs-and-crlf", "First\r\nline.\r\n\r\nSecond paragraph.\n\n\nThird."],
  ["unicode-whitespace", "\ufeffA\u00a0B\u2009C\u3000D\n\nA\u0085B"],
  ["emoji-utf16-measurement", "Harbor 😀 ".repeat(50)],
  ["oversized-word-is-not-split", "A".repeat(100) + " end"],
  [
    "several-pages",
    Array.from(
      { length: 90 },
      (_, index) => `Paragraph ${index}: ` + "Harbor words ".repeat(8),
    ).join("\n\n"),
  ],
  ["arabic-text", "هذا نص عربي للقراءة ".repeat(70)],
  ["small-type", "Small text ".repeat(200), 15, 1.25],
  ["minimum-eight-rows", "Big text ".repeat(180), 100, 3],
  ["empty-content", "\r\n \n\n\ufeff"],
];
const cases = samples.map(([name, text, fontSize = 19, lineHeight = 1.85]) => {
  const input = { text, fontSize, lineHeight, measureFactor: 19 };
  return { name, input, expected: JSON.parse(JSON.stringify(context.reference.layout(input))) };
});
const resumeCases = [
  { starts: [0, 0, 2, 3], target: 0 },
  { starts: [0, 0, 2, 3], target: 2 },
  { starts: [2, 4], target: 0 },
  { starts: [], target: 99 },
].map((input) => ({
  ...input,
  expected: context.reference.pageForParagraph(input.starts, input.target),
}));
const whitespace = Array.from({ length: 65536 }, (_, value) => value).filter((value) =>
  /\s/u.test(String.fromCodePoint(value)),
);
const fixture = {
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: files,
  whitespace,
  paper: context.reference.paper,
  cases,
  resumeCases,
};
assert.equal(cases.length, 9);
assert.equal(whitespace.length, 25);
const target = "ios/HarborTests/Fixtures/book-pagination-reference.json";
await writeFile(target, JSON.stringify(fixture, null, 2) + "\n");
console.log(
  JSON.stringify({
    originalLayoutCases: cases.length,
    originalResumeCases: resumeCases.length,
    whitespaceScalars: whitespace.length,
    target,
  }),
);
