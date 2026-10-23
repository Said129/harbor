import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";
import ts from "typescript";

const argument = process.argv.indexOf("--reference");
assert(argument >= 0 && process.argv[argument + 1]);
const inputs = {
  "src/lib/ebook/translation.ts":
    "de025486a30e1c271e8420555fa00264f460ce556769769b7b73d0c2a66aae69",
  "src/lib/ebook/translation-instructions.md":
    "bccfc4fe67d509f09d292d6c145da0bcbbd366030b1b981822f261c6380d62ba",
  "src/lib/i18n/languages.ts": "feeab8008569c3108c45b91dedb7c471d34426687ac9e6a800eae4947baa4f68",
};
const hash = (value) => createHash("sha256").update(value).digest("hex");
const files = {};
for (const [file, expected] of Object.entries(inputs)) {
  const bytes = await readFile(path.join(process.argv[argument + 1], file));
  assert.equal(hash(bytes), expected);
  files[file] = file.endsWith(".md")
    ? bytes.toString("utf8")
    : bytes.toString("utf8").replaceAll("\r\n", "\n");
}
const original = files["src/lib/ebook/translation.ts"];
const tree = ts.createSourceFile("translation.ts", original, ts.ScriptTarget.Latest, true);
const fn = (name) => {
  const node = tree.statements.find(
    (item) => ts.isFunctionDeclaration(item) && item.name?.text === name,
  );
  assert(node?.body);
  return node;
};
const request = fn("requestTranslation");
const response = request.body.statements.find(
  (item) =>
    ts.isVariableStatement(item) &&
    item.declarationList.declarations[0].name.getText(tree) === "response",
);
const options = response.declarationList.declarations[0].initializer.expression.arguments[1];
const body = options.properties
  .find((item) => item.name.getText(tree) === "body")
  .initializer.arguments[0].getText(tree);
const consume = request.body.statements
  .find(
    (item) =>
      ts.isVariableStatement(item) &&
      item.declarationList.declarations[0].name.getText(tree) === "consume",
  )
  .getText(tree);
const finishStart = request.body.statements.findIndex((item) =>
  item.getText(tree).startsWith('if (finishReason === "length")'),
);
assert(finishStart > 0);
const finish = request.body.statements
  .slice(finishStart)
  .map((item) => item.getText(tree))
  .join("\n");
const languageContext = vm.createContext({});
vm.runInContext(
  ts.transpileModule(files["src/lib/i18n/languages.ts"].replaceAll("export ", ""), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None },
  }).outputText + "\nglobalThis.options=LANGUAGES;",
  languageContext,
);
const languageName = Object.fromEntries(
  languageContext.options.map(({ code, label }) => [code, label]),
);
const source = ts.transpileModule(
  `
const translationInstructions=${JSON.stringify(files["src/lib/ebook/translation-instructions.md"])};
const languageName=${JSON.stringify(languageName)};
const CACHE_PREFIX="harbor.ebook.translation.cache.v1.";
${fn("hash").getText(tree)}
${fn("cacheSlot").getText(tree)}
let decoder=null, clock=0;
const performance={now:()=>clock};
function harborEBookTranslation(raw) {
 const input=JSON.parse(raw),source=input.source??"",title=input.title??"",settings=input.settings??{},model=settings.model?.trim()||"deepseek-v4-flash";
 let result;
 if(input.operation==="prepare") result={slot:cacheSlot(source,title,settings),body:${body}};
 else if(input.operation==="start") {
   decoder=(()=>{
     let firstChunk=0,lastReport=0,output="",finishReason="",progress=null;
     const onProgress=(value)=>{progress=value;};
     ${consume}
     return {feed(line){progress=null;consume(line);if(output.length>16*1024*1024)throw new Error("Translation too large");return progress;},finish(){${finish}}};
   })(); result=null;
 } else if(input.operation==="feed") {if(!decoder)throw new Error("Missing decoder");clock=input.now;result=decoder.feed(input.line);}
 else if(input.operation==="finish") {if(!decoder)throw new Error("Missing decoder");result=decoder.finish();decoder=null;}
 else throw new Error("Unknown translation operation");
 return JSON.stringify(result);
}`,
  { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.None } },
).outputText;
const context = vm.createContext({});
vm.runInContext(source, context, { timeout: 1000 });
const call = (input) => JSON.parse(context.harborEBookTranslation(JSON.stringify(input)));
const settings = { model: "deepseek-v4-flash", targetLanguage: "es" };
const sample = { source: "Original 😀 chapter.", title: "Harbor", settings };
const prepared = call({ operation: "prepare", ...sample });
assert.equal(
  hash(prepared.body.messages[0].content),
  inputs["src/lib/ebook/translation-instructions.md"],
);
assert.equal(prepared.body.messages[0].content, files["src/lib/ebook/translation-instructions.md"]);
assert.equal(prepared.body.thinking.type, "disabled");
assert.equal(prepared.body.messages[1].content.includes("target_language: Spanish"), true);
const cases = [];
function stream(name, pieces, finishReason, expected) {
  const operations = [
    { operation: "start", ...sample },
    { operation: "feed", line: ": heartbeat", now: 1000 },
    ...pieces.map((content, index) => ({
      operation: "feed",
      now: 1500 + index * 300,
      line: "data: " + JSON.stringify({ choices: [{ delta: { content } }] }),
    })),
    {
      operation: "feed",
      now: 9000,
      line: "data: " + JSON.stringify({ choices: [{ finish_reason: finishReason }] }),
    },
    { operation: "feed", now: 9300, line: "data: [DONE]" },
    { operation: "finish" },
  ];
  const results = [];
  let failure;
  try {
    for (const operation of operations) results.push(call(operation));
  } catch (error) {
    failure = error.message;
  }
  if (typeof expected === "string") assert.equal(failure, expected);
  else assert.deepEqual(results.at(-1), expected);
  cases.push({ name, operations, results, failure: failure ?? null });
}
stream(
  "split XML and multilingual text",
  ["<chapter_t", "itle>Puerto</chapter_title><chapter_body>Hola 😀\n\nالعربية", "</chapter_body>"],
  "stop",
  { title: "Puerto", text: "Hola 😀\n\nالعربية" },
);
stream(
  "empty translated title keeps source title",
  ["<chapter_title> </chapter_title><chapter_body>Capítulo</chapter_body>"],
  "stop",
  { title: "Harbor", text: "Capítulo" },
);
stream(
  "fenced XML",
  ["```xml\n<chapter_title>Puerto</chapter_title><chapter_body>Capítulo</chapter_body>\n```"],
  "stop",
  { title: "Puerto", text: "Capítulo" },
);
stream(
  "truncation rejects even a complete XML body",
  ["<chapter_body>Texto</chapter_body>"],
  "length",
  "DeepSeek translation was truncated",
);
stream(
  "filtered output rejects partial chapter",
  ["<chapter_body>Texto</chapter_body>"],
  "content_filter",
  "DeepSeek stopped translation: content filter",
);
stream(
  "missing body is not a translation",
  ["<chapter_title>Puerto</chapter_title>"],
  "stop",
  "DeepSeek returned an incomplete chapter translation",
);
stream("empty stream", [], "stop", "DeepSeek returned no translation");
const slots = [
  sample,
  { ...sample, settings: { ...settings, model: " deepseek-v4-pro " } },
  { ...sample, settings: { ...settings, targetLanguage: "ar" } },
  { ...sample, source: "Changed chapter" },
].map((input) => ({ input, expected: call({ operation: "prepare", ...input }).slot }));
assert.equal(new Set(slots.map((item) => item.expected)).size, 4);
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs,
  instructionSHA256: inputs["src/lib/ebook/translation-instructions.md"],
  program: { source, sha256: hash(source) },
};
await writeFile("ios/Harbor/EBookTranslationAssets.json", JSON.stringify(asset) + "\n");
await writeFile(
  "ios/HarborTests/Fixtures/ebook-translation-reference.json",
  JSON.stringify({ cases, slots, request: { input: sample, expected: prepared } }) + "\n",
);
console.log(
  JSON.stringify({
    programSHA256: asset.program.sha256,
    originalStreamCases: cases.length,
    originalCacheCases: slots.length,
    instructionSHA256: asset.instructionSHA256,
  }),
);
