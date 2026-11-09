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
const revision = "0834340cec5531650bfe78cd628628702e636987";
const ts = createRequire(path.join(repo, "package.json"))("typescript");
const inputs = {};
const committedInputs = {};

if (JSON.parse(fs.readFileSync(path.join(reference, "package.json"), "utf8")).version !== "0.9.132")
  throw Error("Wrong Desktop reference");

const read = (relative) => {
  const data = fs.readFileSync(path.join(reference, relative));
  const original = execFileSync("git", ["show", revision + ":" + relative], { cwd: repo });
  const normalized = (value) => value.toString("utf8").replace(/\r\n/g, "\n");
  if (normalized(data) !== normalized(original)) throw Error("Changed original input " + relative);
  const key = relative.replaceAll("\\", "/");
  committedInputs[key] = crypto.createHash("sha256").update(original).digest("hex");
  inputs[key] = crypto.createHash("sha256").update(data).digest("hex");
  return data.toString("utf8");
};

const compile = (source) =>
  ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
const sourceFiles = {
  pivot: "src/lib/subtitles/autosync/pivot.ts",
  alignmentFit: "src/lib/subtitles/autosync/alignment-fit.ts",
  monotonicAlign: "src/lib/subtitles/autosync/monotonic-align.ts",
  arabicQuality: "src/lib/subtitles/arabic-quality.ts",
  candidateRanking: "src/lib/subtitles/candidate-ranking.ts",
  releaseMatch: "src/lib/subtitles/release-match.ts",
  streamHints: "src/lib/subtitles/stream-hints.ts",
};
const originals = Object.fromEntries(
  Object.entries(sourceFiles).map(([name, relative]) => [name, read(relative)]),
);
const sourceFile = ts.createSourceFile(
  sourceFiles.candidateRanking,
  originals.candidateRanking,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const declaration = sourceFile.statements.find(
  (node) => ts.isFunctionDeclaration(node) && node.name?.text === "stableTextCompare",
);
if (
  !declaration ||
  !declaration.body ||
  !declaration.modifiers?.some((item) => item.kind === ts.SyntaxKind.ExportKeyword)
)
  throw Error("Pinned stableTextCompare helper unavailable");
const stableTextCompare = compile(declaration.getText(sourceFile));

const source = `
(()=>{
const factories={
  "pivot":(module,exports,require)=>{${compile(originals.pivot)}\n},
  "alignment-fit":(module,exports,require)=>{${compile(originals.alignmentFit)}\n},
  "monotonic-align":(module,exports,require)=>{${compile(originals.monotonicAlign)}\n},
  "arabic-quality":(module,exports,require)=>{${compile(originals.arabicQuality)}\n},
  "release-match":(module,exports,require)=>{${compile(originals.releaseMatch)}\n},
  "stream-hints":(module,exports,require)=>{${compile(originals.streamHints)}\n},
  "candidate-ranking":(module,exports)=>{${stableTextCompare}\n}
};
const cache=Object.create(null);
function requireModule(from,request){
  if(request==="@/lib/subtitles/candidate-ranking")request="candidate-ranking";
  const base=from.includes("/")?from.slice(0,from.lastIndexOf("/")+1):"";
  const id=(base+request).replace(/^\\.\\//,"");
  if(cache[id])return cache[id].exports;
  const factory=factories[id];
  if(!factory)throw Error("Unavailable bundled module: "+id);
  const module={exports:{}};cache[id]=module;
  factory(module,module.exports,(child)=>requireModule(id,child));
  return module.exports;
}
const pivot=requireModule("","./pivot");
const arabic=requireModule("","./arabic-quality");
const release=requireModule("","./release-match");
const stream=requireModule("","./stream-hints");
const MAX_CUES=8000,MAX_CUE_TEXT=2000,MAX_CUE_TEXT_TOTAL=120000,MAX_RAW_TEXT=2000000;
let status="idle",activeRequest=null,workflowResult=null,workflowError=null;
let generation=0,nextRequestID=0;

function finite(value){return typeof value==="number"&&Number.isFinite(value);}
function validateCues(raw,name){
  if(!Array.isArray(raw)||raw.length>MAX_CUES)throw Error("Invalid "+name+" cue count");
  let total=0;
  const cues=raw.map((cue)=>{
    if(!cue||!finite(cue.start)||!finite(cue.end)||cue.end<=cue.start||typeof cue.text!=="string")
      throw Error("Invalid "+name+" cue");
    if(cue.text.length>MAX_CUE_TEXT)throw Error("Oversized "+name+" cue text");
    total+=cue.text.length;
    if(total>MAX_CUE_TEXT_TOTAL)throw Error("Oversized "+name+" cue text collection");
    return {start:cue.start,end:cue.end,text:cue.text};
  });
  return cues;
}
function validateInput(raw){
  if(!raw||typeof raw!=="object")throw Error("Missing pivot workflow input");
  if(typeof raw.audioLanguage!=="string"||raw.audioLanguage.length>80||
     typeof raw.subtitleLanguage!=="string"||raw.subtitleLanguage.length>80)
    throw Error("Invalid pivot languages");
  if(typeof raw.targetHealthy!=="boolean"||typeof raw.targetFormatSafe!=="boolean"||typeof raw.calibrationReady!=="boolean")
    throw Error("Invalid pivot safety flags");
  if(raw.maxCandidates!==undefined&&raw.maxCandidates!==null&&
     (!Number.isInteger(raw.maxCandidates)||raw.maxCandidates<1||raw.maxCandidates>5))
    throw Error("Invalid pivot candidate limit");
  if(raw.bestEffort!==undefined&&typeof raw.bestEffort!=="boolean")throw Error("Invalid best-effort flag");
  return {audioLanguage:raw.audioLanguage,subtitleLanguage:raw.subtitleLanguage,
    targetCues:validateCues(raw.targetCues,"target"),targetHealthy:raw.targetHealthy,
    targetFormatSafe:raw.targetFormatSafe,calibrationReady:raw.calibrationReady,
    ...(raw.maxCandidates===undefined||raw.maxCandidates===null?{}:{maxCandidates:raw.maxCandidates}),
    ...(raw.bestEffort===undefined?{}:{bestEffort:raw.bestEffort})};
}
function noURL(value,name,max){
  if(typeof value!=="string"||value.length===0||value.length>max||value.includes("://"))
    throw Error("Invalid "+name);
  return value;
}
function validateCandidates(raw){
  if(!Array.isArray(raw)||raw.length>100)throw Error("Invalid pivot candidate list");
  return raw.map((candidate)=>{
    if(!candidate||typeof candidate!=="object"||typeof candidate.exactRelease!=="boolean"||
       !finite(candidate.releaseScore))throw Error("Invalid pivot candidate");
    const clean={id:noURL(candidate.id,"candidate id",2048),
      language:noURL(candidate.language,"candidate language",80),
      exactRelease:candidate.exactRelease,releaseScore:candidate.releaseScore};
    for(const key of ["wrongEditionRisk","popularity"]){
      if(candidate[key]!==undefined){if(!finite(candidate[key]))throw Error("Invalid candidate "+key);clean[key]=candidate[key];}
    }
    if(candidate.source!==undefined)clean.source=noURL(candidate.source,"candidate source",128);
    return clean;
  });
}
function validateTransform(raw){
  if(!raw||typeof raw!=="object")throw Error("Invalid sync transform");
  if(raw.kind==="affine"){
    if(!finite(raw.offsetSec)||!finite(raw.ratio))throw Error("Invalid affine transform");
    return {kind:"affine",offsetSec:raw.offsetSec,ratio:raw.ratio};
  }
  if(raw.kind==="piecewise"){
    if(!Array.isArray(raw.segments)||raw.segments.length>256)throw Error("Invalid piecewise transform");
    return {kind:"piecewise",segments:raw.segments.map((segment)=>{
      if(!segment||![segment.fromSec,segment.toSec,segment.offsetSec,segment.ratio].every(finite))
        throw Error("Invalid piecewise segment");
      return {fromSec:segment.fromSec,toSec:segment.toSec,offsetSec:segment.offsetSec,ratio:segment.ratio};
    })};
  }
  throw Error("Unknown sync transform");
}
function validatePrepared(raw){
  if(!raw||typeof raw!=="object"||typeof raw.healthy!=="boolean"||typeof raw.formatSafe!=="boolean")
    throw Error("Invalid prepared pivot candidate");
  const value={cues:validateCues(raw.cues,"pivot"),healthy:raw.healthy,formatSafe:raw.formatSafe};
  if(raw.diagnostics!==undefined){
    if(!Array.isArray(raw.diagnostics)||raw.diagnostics.length>200||raw.diagnostics.some((x)=>typeof x!=="string"||x.length>512))
      throw Error("Invalid pivot diagnostics");
    value.diagnostics=raw.diagnostics;
  }
  return value;
}
function validatePivotAudio(raw){
  if(!raw||typeof raw!=="object"||typeof raw.validated!=="boolean"||!finite(raw.score)||!finite(raw.coverage))
    throw Error("Invalid pivot audio validation");
  const value={validated:raw.validated,transform:validateTransform(raw.transform),score:raw.score,coverage:raw.coverage};
  if(raw.wrongCut!==undefined){if(typeof raw.wrongCut!=="boolean")throw Error("Invalid wrong-cut flag");value.wrongCut=raw.wrongCut;}
  if(raw.diagnostics!==undefined){
    if(!Array.isArray(raw.diagnostics)||raw.diagnostics.length>200||raw.diagnostics.some((x)=>typeof x!=="string"||x.length>512))
      throw Error("Invalid pivot diagnostics");
    value.diagnostics=raw.diagnostics;
  }
  return value;
}
function validateTargetAudio(raw){
  if(!raw||typeof raw!=="object"||!finite(raw.qualityBefore)||!finite(raw.qualityAfter)||
     !finite(raw.coverage)||typeof raw.heldOutAudioMeasured!=="boolean")
    throw Error("Invalid target audio validation");
  const value={qualityBefore:raw.qualityBefore,qualityAfter:raw.qualityAfter,
    coverage:raw.coverage,heldOutAudioMeasured:raw.heldOutAudioMeasured};
  if(raw.wrongCut!==undefined){if(typeof raw.wrongCut!=="boolean")throw Error("Invalid final wrong-cut flag");value.wrongCut=raw.wrongCut;}
  return value;
}
function output(extra={}){
  return JSON.stringify({status,request:activeRequest?{id:activeRequest.id,operation:activeRequest.operation,payload:activeRequest.payload}:null,
    result:workflowResult,error:workflowError,...extra});
}
function issue(owner,operation,payload){
  if(owner!==generation||status!=="running")throw Error("Retired pivot workflow");
  if(activeRequest)throw Error("Concurrent native pivot requests are not supported");
  const id=generation+":"+(++nextRequestID);
  return new Promise((resolve,reject)=>{activeRequest={id,operation,payload,resolve,reject};});
}
function portValue(operation,raw){
  switch(operation){
    case "searchPivotCandidates":return validateCandidates(raw);
    case "preparePivotCandidate":return validatePrepared(raw);
    case "validatePivotAgainstAudio":return validatePivotAudio(raw);
    case "validateTargetAgainstAudio":return validateTargetAudio(raw);
    default:throw Error("Unknown pending pivot request");
  }
}
function invalidate(reason){
  generation+=1;
  const request=activeRequest;activeRequest=null;
  if(request)request.reject(Error(reason||"Pivot workflow cancelled"));
}
function start(raw,validateTarget){
  const input=validateInput(raw);
  if(typeof validateTarget!=="boolean")throw Error("Invalid target audio port setting");
  invalidate("Pivot workflow replaced");
  workflowResult=null;workflowError=null;status="running";
  const owner=generation;
  const ports={
    searchPivotCandidates:(audioLanguage)=>issue(owner,"searchPivotCandidates",{audioLanguage}),
    preparePivotCandidate:(candidate)=>issue(owner,"preparePivotCandidate",{candidate}),
    validatePivotAgainstAudio:(candidate,prepared)=>issue(owner,"validatePivotAgainstAudio",{candidate,prepared})
  };
  if(validateTarget)ports.validateTargetAgainstAudio=(targetCues,transform,heldOutWindows)=>
    issue(owner,"validateTargetAgainstAudio",{targetCues,transform,heldOutWindows});
  void pivot.runPivotWorkflow(input,ports).then((result)=>{
    if(owner!==generation)return;
    workflowResult=result;status="completed";activeRequest=null;
  },()=>{
    if(owner!==generation)return;
    status="failed";workflowError="workflow-failed";activeRequest=null;
  });
  return output();
}
function complete(request){
  if(typeof request.requestID!=="string"||!activeRequest||activeRequest.id!==request.requestID||
     !request.requestID.startsWith(generation+":"))return output({accepted:false});
  let value;
  try{value=portValue(activeRequest.operation,request.result);}catch(error){
    const pending=activeRequest;activeRequest=null;pending.reject(error);return output({accepted:false});
  }
  const pending=activeRequest;activeRequest=null;pending.resolve(value);
  return output({accepted:true});
}
function reject(request){
  if(typeof request.requestID!=="string"||!activeRequest||activeRequest.id!==request.requestID||
     !request.requestID.startsWith(generation+":"))return output({accepted:false});
  const pending=activeRequest;activeRequest=null;pending.reject(Error("Native pivot port failed"));
  return output({accepted:true});
}
function releaseConfidences(request){
  const raw=request.hints,texts=request.subtitleTexts;
  if(!raw||typeof raw!=="object"||!Array.isArray(texts)||texts.length>512)
    throw Error("Invalid release matching request");
  const hints={};
  for(const key of ["release","source","resolution"]){
    if(raw[key]!==undefined&&raw[key]!==null)hints[key]=noURL(raw[key],key,2000);
  }
  for(const key of ["season","episode"]){
    if(raw[key]===undefined||raw[key]===null)continue;
    if(!Number.isSafeInteger(raw[key])||raw[key]<0)throw Error("Invalid release episode");
    hints[key]=raw[key];
  }
  const tags=stream.streamTagsOf(hints);
  return JSON.stringify({values:texts.map((value)=>release.releaseAffinity(tags,value===""?"":noURL(value,"subtitle descriptor",2000)).confidence)});
}
function arabicCueHealth(request){
  if(typeof request.rawText!=="string"||request.rawText.length>MAX_RAW_TEXT)throw Error("Invalid Arabic subtitle text");
  const cues=validateCues(request.cues,"Arabic");
  const quality=arabic.analyzeArabicSubtitleQuality(request.rawText,cues);
  return JSON.stringify({healthy:quality.healthy&&quality.arabicCueRatio>=0.5,
    quality:{healthy:quality.healthy,arabicCueRatio:quality.arabicCueRatio}});
}
function handle(request){
  if(!request||typeof request!=="object")throw Error("Invalid pivot request");
  switch(request.operation){
    case "start":return start(request.input,request.validateTargetAgainstAudio);
    case "complete":return complete(request);
    case "reject":return reject(request);
    case "drain":return output();
    case "cancel":
      if(status==="running")invalidate("Pivot workflow cancelled");
      workflowResult=null;workflowError=null;status="cancelled";
      return output();
    case "releaseConfidences":return releaseConfidences(request);
    case "arabicCueHealth":return arabicCueHealth(request);
    default:throw Error("Unknown subtitle pivot operation");
  }
}
globalThis.harborSubtitlePivotWorkflow=(raw)=>handle(JSON.parse(raw));
})();`;

for (const forbidden of ["@tauri-apps", "XMLHttpRequest", "fetch(", "node:fs", "FileManager"]) {
  if (source.includes(forbidden))
    throw Error("Unexpected runtime capability in JS asset: " + forbidden);
}

const asset = {
  schema: 1,
  reference: revision,
  inputs,
  committed_inputs: committedInputs,
  original_modules: Object.keys(sourceFiles).length,
  pure_workflow_with_native_ports: true,
  held_out_audio_is_native_only: true,
  program: { source, sha256: crypto.createHash("sha256").update(source).digest("hex") },
};
fs.writeFileSync(
  path.join(repo, "ios/Harbor/SubtitlePivotWorkflowAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
console.log(
  JSON.stringify({
    original_modules: asset.original_modules,
    program_bytes: Buffer.byteLength(source),
    sha256: asset.program.sha256,
    pure_workflow_with_native_ports: true,
    held_out_audio_is_native_only: true,
  }),
);
