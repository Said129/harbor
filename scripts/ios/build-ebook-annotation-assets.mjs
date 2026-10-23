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
const variables = new Map();
function visit(node) {
  if (ts.isVariableDeclaration(node)) variables.set(node.name.getText(tree), node);
  ts.forEachChild(node, visit);
}
visit(tree);
const definitions = ["marks", "stripMarks", "referenceRanges", "inks"]
  .map((name) => {
    const node = variables.get(name);
    assert(node?.initializer);
    return "const " + node.getText(tree) + ";";
  })
  .join("\n");
const render = variables.get("renderText").initializer.body;
const ranges = render.statements
  .find(
    (item) =>
      ts.isVariableStatement(item) &&
      item.declarationList.declarations[0].name.getText(tree) === "ranges",
  )
  .getText(tree);
const source = ts.transpileModule(
  `${definitions}
function annotationRuns(text,line,chapter,annotations) {
 ${ranges}
 let cursor=0;
 const result=[];
 ranges.forEach(({start:rawStart,end:rawEnd,annotation})=>{
   const start=Math.max(cursor,Math.min(text.length,rawStart));
   const end=Math.max(start,Math.min(text.length,rawEnd));
   if(end>start)result.push({start,end,id:annotation.id,color:annotation.color,density:annotation.density});
   cursor=end;
 });
 return result;
}
function harborEBookAnnotations(raw) {
 const input=JSON.parse(raw);
 if(input.operation==="inks")return JSON.stringify(inks);
 const text=input.text??"",line=input.line??0,chapter={id:input.chapterId},annotations=input.annotations??[];
 if(input.operation==="reference")return JSON.stringify(referenceRanges(text,input.phrase??""));
 if(input.operation==="chapter")return JSON.stringify(input.paragraphs.map(p=>({line:p.line,runs:annotationRuns(p.text,p.line,chapter,annotations)})).filter(p=>p.runs.length));
 return JSON.stringify(annotationRuns(text,line,chapter,annotations));
}`,
  { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None } },
).outputText;
const context = vm.createContext({});
vm.runInContext(source, context, { timeout: 1000 });
const call = (input) => JSON.parse(context.harborEBookAnnotations(JSON.stringify(input)));
const palette = call({ operation: "inks" });
assert.equal(palette.length, 8);
const note = (id, chapterId, ranges, extra = {}) => ({
  id,
  chapterId,
  ranges,
  color: palette[0],
  density: 58,
  reference: false,
  text: "",
  ...extra,
});
const cases = [];
function check(name, input, inspect) {
  const expected = call(input);
  inspect(expected);
  cases.push({ name, input, expected });
}
check(
  "accent insensitive whole words",
  { operation: "reference", text: "Café cafe CAFÉ cafeteria", phrase: "cafe" },
  (r) => assert.equal(r.length, 3),
);
check(
  "Arabic marks retain original offsets",
  { operation: "reference", text: "هٰذَا كِتَابٌ ثم كتاب", phrase: "كتاب" },
  (r) => assert.equal(r.length, 2),
);
check(
  "UTF16 offsets include preceding emoji",
  { operation: "reference", text: "😀 Café 😀 café", phrase: "cafe" },
  (r) => assert.equal(r[0].start, 3),
);
check("empty phrase", { operation: "reference", text: "Harbor", phrase: "  " }, (r) =>
  assert.equal(r.length, 0),
);
check(
  "same chapter direct range",
  {
    text: "Harbor passage",
    line: 2,
    chapterId: "source:one",
    annotations: [note("one", "source:one", [{ line: 2, start: 1, end: 6 }])],
  },
  (r) =>
    assert.deepEqual(
      r.map(({ start, end }) => [start, end]),
      [[1, 6]],
    ),
);
check(
  "another chapter cannot paint a direct note",
  {
    text: "Harbor passage",
    line: 2,
    chapterId: "source:other",
    annotations: [note("one", "source:one", [{ line: 2, start: 1, end: 6 }])],
  },
  (r) => assert.equal(r.length, 0),
);
check(
  "reference phrase recurs across chapters",
  {
    text: "Harbor harbor harbors",
    line: 0,
    chapterId: "source:other",
    annotations: [note("one", "source:one", [], { reference: true, text: "harbor" })],
  },
  (r) => assert.equal(r.length, 2),
);
check(
  "longer overlapping range takes precedence",
  {
    text: "Harbor passage",
    line: 0,
    chapterId: "source:one",
    annotations: [
      note("small", "source:one", [{ line: 0, start: 0, end: 3 }]),
      note("long", "source:one", [{ line: 0, start: 0, end: 8 }]),
    ],
  },
  (r) => assert.equal(r[0].id, "long"),
);
check(
  "clamped end never exceeds the original text",
  {
    text: "Harbor",
    line: 0,
    chapterId: "source:one",
    annotations: [note("one", "source:one", [{ line: 0, start: 3, end: 999 }])],
  },
  (r) => assert.equal(r[0].end, 6),
);
check(
  "same chapter reference does not paint duplicate overlap",
  {
    text: "Harbor",
    line: 0,
    chapterId: "source:one",
    annotations: [
      note("one", "source:one", [{ line: 0, start: 0, end: 6 }], {
        reference: true,
        text: "Harbor",
      }),
    ],
  },
  (r) => assert.equal(r.length, 1),
);
check(
  "batch chapter returns only painted lines",
  {
    operation: "chapter",
    paragraphs: [
      { line: 0, text: "Harbor" },
      { line: 1, text: "Another passage" },
    ],
    chapterId: "source:one",
    annotations: [note("one", "source:one", [{ line: 0, start: 0, end: 6 }])],
  },
  (r) => {
    assert.equal(r.length, 1);
    assert.equal(r[0].line, 0);
    assert.equal(r[0].runs[0].id, "one");
  },
);
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: { [file]: inputHash },
  inks: palette,
  program: { source, sha256: hash(source) },
};
await writeFile("ios/Harbor/EBookAnnotationAssets.json", JSON.stringify(asset) + "\n");
await writeFile(
  "ios/HarborTests/Fixtures/ebook-annotation-reference.json",
  JSON.stringify({ palette, cases }) + "\n",
);
console.log(
  JSON.stringify({
    programSHA256: asset.program.sha256,
    originalCases: cases.length,
    originalInks: palette.length,
  }),
);
