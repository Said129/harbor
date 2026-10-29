import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const reference = path.resolve(
  process.argv[2] ?? path.join(repo, "../harbor-revision/parity132/desktop-0.9.132"),
);
const ts = createRequire(path.join(repo, "package.json"))("typescript"),
  inputs = {};
const revision = "0834340cec5531650bfe78cd628628702e636987",
  committedInputs = {};
if (JSON.parse(fs.readFileSync(path.join(reference, "package.json"), "utf8")).version !== "0.9.132")
  throw Error("Wrong Desktop reference");
const read = (relative) => {
  const data = fs.readFileSync(path.join(reference, relative));
  const original = execFileSync("git", ["show", revision + ":" + relative], { cwd: repo });
  if (
    data.toString("utf8").replace(/\r\n/g, "\n") !==
    original.toString("utf8").replace(/\r\n/g, "\n")
  )
    throw Error("Changed original input " + relative);
  committedInputs[relative] = crypto.createHash("sha256").update(original).digest("hex");
  inputs[relative] = crypto.createHash("sha256").update(data).digest("hex");
  return data.toString("utf8");
};
const compile = (source) =>
  ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
const version = read("src/lib/music/source-version.ts"),
  queue = read("src/lib/music/queue-source.ts");
const sources = read("src/lib/music/sources.ts"),
  play = read("src/lib/music/play-track.ts");
const parse = (name, source) =>
  ts.createSourceFile(name, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
const sourceTree = parse("sources.ts", sources),
  playTree = parse("play-track.ts", play);
const musicSourceKey = playTree.statements
  .filter(ts.isVariableStatement)
  .flatMap((node) => node.declarationList.declarations)
  .find((node) => node.name.getText(playTree) === "MUSIC_SOURCE_KEY");
if (!musicSourceKey) throw Error("Original playback preference key unavailable");
const functions = new Map(
  sourceTree.statements.filter(ts.isFunctionDeclaration).map((n) => [n.name.text, n]),
);
const constants = new Map(
  sourceTree.statements
    .filter(ts.isVariableStatement)
    .flatMap((n) => n.declarationList.declarations.map((d) => [d.name.getText(sourceTree), d])),
);
const functionText = (name) => {
  const node = functions.get(name);
  if (!node) throw Error("Missing original function " + name);
  return node.getText(sourceTree).replace(/^export\s+/, "");
};
const constantText = (name) => {
  const node = constants.get(name);
  if (!node) throw Error("Missing original constant " + name);
  return "const " + name + "=" + node.initializer.getText(sourceTree) + ";";
};
const candidateFunction = functions.get("getMusicSourceCandidates");
let vocalFilter = null;
function visit(node) {
  if (
    ts.isCallExpression(node) &&
    ts.isPropertyAccessExpression(node.expression) &&
    node.expression.name.text === "then" &&
    ts.isArrowFunction(node.arguments[0])
  )
    vocalFilter = node.arguments[0].body.getText(sourceTree);
  ts.forEachChild(node, visit);
}
visit(candidateFunction);
if (!vocalFilter?.startsWith("candidates.filter("))
  throw Error("Actual original vocal filter changed");
const resolver = playTree.statements.find(
  (n) => ts.isFunctionDeclaration(n) && n.name.text === "resolveAndPlayMusicTrack",
);
const statements = resolver.body.statements;
const declarationName = (node) =>
  ts.isVariableStatement(node) ? node.declarationList.declarations[0].name.getText(playTree) : null;
const first = statements.findIndex((node) => declarationName(node) === "usable");
const last = statements.findIndex((node) => declarationName(node) === "selectedQueue");
const preferred = statements
  .find((node) => declarationName(node) === "preferred")
  .getText(playTree);
const direct = statements.find(
  (node) => ts.isIfStatement(node) && node.expression.getText(playTree) === "track.playbackUrl",
);
const directReturn = direct.thenStatement.statements.find(ts.isReturnStatement).getText(playTree);
const final = statements.at(-1).getText(playTree);
if (first < 0 || last <= first || !final.startsWith("return "))
  throw Error("Actual original choice block changed");
const choose =
  "function choose(track,queue,candidates){" +
  preferred +
  "if(track.playbackUrl){" +
  directReturn +
  "}candidates=" +
  vocalFilter +
  ";" +
  statements
    .slice(first, last + 1)
    .map((n) => n.getText(playTree))
    .join("\n") +
  final +
  "}";
const program = compile(`
const version=(()=>{const exports={};${compile(version)};return exports;})();
const queueSource=(()=>{const exports={};${compile(queue)};return exports;})();
let preference=null;
const readMusicPreference=()=>preference;
const MUSIC_SOURCE_KEY=${musicSourceKey.initializer.getText(playTree)};
${["PREFERRED_SOURCE_KEY", "MUSIC_SOURCE_ORDER", "DEFAULT_PLAYBACK_SOURCE"].map(constantText).join("\n")}
${["musicSourcePriority", "preferredMusicSource", "musicPlaybackSource"].map(functionText).join("\n")}
const compatibleVocalVersion=version.compatibleVocalVersion;
const adoptRequestedIdentity=queueSource.adoptRequestedIdentity;
${choose}
globalThis.harborMusicSourcePolicy=raw=>{
 const request=JSON.parse(raw);preference=request.preferred??null;
 const track=request.track,queue=request.queue??[track];
 let result;
 switch(request.operation){
 case 'adopt':result=queueSource.adoptRequestedIdentity(request.selected,track);break;
 case 'replace':result=queueSource.replaceQueueTrack(queue,request.index,request.selected);break;
 case 'selectable':result=queueSource.selectableSources(request.candidates,track);break;
 case 'backing':result=version.backingTrackVersion(track);break;
 case 'compatible':result=version.compatibleVocalVersion(track,request.selected);break;
 case 'preferred':result=preferredMusicSource();break;
 case 'priority':result=musicSourcePriority(request.connectorId);break;
 case 'playbackSource':result=musicPlaybackSource(request.connectorId);break;
 case 'shouldResolve':result=version.shouldResolvePreferredSource(track,request.preferred,request.explicit??false,request.failed??false);break;
 case 'choose':result=choose(track,queue,request.candidates);break;
 default:throw Error('Unknown music source policy operation');
 }
 return JSON.stringify(result);
};`);
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs,
  committed_inputs: committedInputs,
  original_modules: 4,
  pure_original_selection_and_identity_logic: true,
  provider_or_playback_requests_performed: false,
  program: { source: program, sha256: crypto.createHash("sha256").update(program).digest("hex") },
};
fs.writeFileSync(
  path.join(repo, "ios/Harbor/MusicSourcePolicyAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
console.log(
  JSON.stringify({
    original_modules: 4,
    program_bytes: Buffer.byteLength(program),
    sha256: asset.program.sha256,
    provider_or_playback_requests_performed: false,
  }),
);
