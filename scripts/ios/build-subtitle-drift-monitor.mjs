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

const files = {
  "drift-monitor": "src/lib/subtitles/autosync/drift-monitor.ts",
  "drift-dsp": "src/lib/subtitles/autosync/drift-dsp.ts",
  "fp-gate": "src/lib/subtitles/autosync/fp-gate.ts",
  confidence: "src/lib/subtitles/autosync/confidence.ts",
};
const modules = Object.fromEntries(
  Object.entries(files).map(([name, file]) => [name, compile(read(file))]),
);

const source = `
(()=>{
const factories={
  "drift-monitor":(module,exports,require)=>{${modules["drift-monitor"]}\n},
  "drift-dsp":(module,exports,require)=>{${modules["drift-dsp"]}\n},
  "fp-gate":(module,exports,require)=>{${modules["fp-gate"]}\n},
  "confidence":(module,exports,require)=>{${modules.confidence}\n},
  // Drift ports are a type boundary in the iOS build. The Tauri adapter is deliberately absent.
  "drift-ports":(module)=>{module.exports={};}
};
const cache=Object.create(null);
function requireModule(from,request){
  const base=from.includes("/")?from.slice(0,from.lastIndexOf("/")+1):"";
  const id=(base+request).replace(/^\\.\\//,"");
  if(cache[id])return cache[id].exports;
  const factory=factories[id];
  if(!factory)throw Error("Unavailable bundled module: "+id);
  const module={exports:{}};cache[id]=module;
  factory(module,module.exports,(child)=>requireModule(id,child));
  return module.exports;
}
const api=requireModule("","./drift-monitor");
const defaults=api.DEFAULT_DRIFT_CONFIG;
let monitor=null,current=null,lastObserved=null,generation=0,nextID=0;
let cachedCues=[],pendingRequests=new Map(),lastCompletedDelay=null;
let lastOfferObject=null,offerBasisDelay=null,skipSamplesUntil=-Infinity,capturedDelay=null;

function finite(value){return typeof value==="number"&&Number.isFinite(value);}
function normalize(raw,fallbackCues=[]){
  if(!raw||typeof raw!=="object")throw Error("Missing playback snapshot");
  for(const key of ["positionSec","durationSec","subDelaySec","rate"])
    if(!finite(raw[key]))throw Error("Invalid playback snapshot: "+key);
  if(typeof raw.trackKey!=="string"||raw.trackKey.length===0||raw.trackKey.length>4096)
    throw Error("Invalid playback identity");
  if(typeof raw.playing!=="boolean"||typeof raw.buffering!=="boolean")
    throw Error("Invalid playback flags");
  const nowMs=raw.nowMs===undefined||raw.nowMs===null?Date.now():raw.nowMs;
  if(!finite(nowMs))throw Error("Invalid playback clock");
  let cues=fallbackCues;
  if(Array.isArray(raw.cues)){
    if(raw.cues.length>100000)throw Error("Too many subtitle cue timings");
    cues=raw.cues.map((cue)=>{
      if(!cue||!finite(cue.startSec)||!finite(cue.endSec)||cue.endSec<=cue.startSec)
        throw Error("Invalid subtitle cue timing");
      return {start:cue.startSec,end:cue.endSec};
    });
  }
  return {trackKey:raw.trackKey,positionSec:raw.positionSec,durationSec:raw.durationSec,
    subDelaySec:raw.subDelaySec,playing:raw.playing,buffering:raw.buffering,rate:raw.rate,
    nowMs,cues};
}
function playerState(){
  if(!current)throw Error("Playback snapshot unavailable");
  return {trackKey:current.trackKey,positionSec:current.positionSec,durationSec:current.durationSec,
    subDelaySec:current.subDelaySec,playing:current.playing,buffering:current.buffering,
    rate:current.rate,cues:current.cues};
}
function cancelPending(reason){
  generation+=1;
  for(const [id,request] of pendingRequests){
    pendingRequests.delete(id);
    request.reject(Error(reason||"Speech request discarded"));
  }
}
function makeMonitor(){
  const ports={sampleSpeech:(startSec,lenSec)=>new Promise((resolve,reject)=>{
    if(pendingRequests.size!==0){reject(Error("Speech request already pending"));return;}
    const id=generation+":"+(++nextID);
    pendingRequests.set(id,{resolve,reject,startSec,lenSec,delayAtStart:current.subDelaySec,generation});
  })};
  const deps={getState:playerState,setSubDelay:(value)=>{capturedDelay=finite(value)?value:null;},
    now:()=>current?.nowMs??Date.now()};
  monitor=new api.DriftMonitor(ports,deps);
  lastOfferObject=null;offerBasisDelay=null;
}
function seeked(previous,next){
  if(!previous)return false;
  const posDelta=next.positionSec-previous.positionSec;
  const wallDelta=Math.max(0,(next.nowMs-previous.nowMs)/1000)*(next.rate||1);
  return posDelta<-.5||(next.playing&&posDelta-wallDelta>defaults.seekTolSec);
}
function monitorObserveFor(snapshot,suppressSample){
  const oldPlaying=snapshot.playing;
  if(suppressSample)snapshot.playing=false;
  try{monitor.observe();}finally{snapshot.playing=oldPlaying;}
}
function state(extra={}){
  const offer=monitor?.pendingOffer??null;
  if(offer&&offer!==lastOfferObject){lastOfferObject=offer;offerBasisDelay=lastCompletedDelay??current?.subDelaySec??null;}
  if(!offer){lastOfferObject=null;offerBasisDelay=null;}
  const request=[...pendingRequests.entries()].find(([,value])=>value.generation===generation);
  const result={status:monitor?.status??"idle",sampleRequest:request?{id:request[0],startSec:request[1].startSec,lenSec:request[1].lenSec}:null,
    correction:offer?{residualSec:offer.residualSec,stepSec:offer.stepSec,pCorrect:offer.pCorrect}:null,
    appliedDelaySec:capturedDelay,correctionTotalSec:monitor?.correctionTotalSec??0,...extra};
  capturedDelay=null;
  return JSON.stringify(result);
}
function setSnapshot(raw){current=normalize(raw,cachedCues);cachedCues=current.cues;return current;}
function resetIdentity(snapshot){
  cancelPending("Playback identity changed");
  current=snapshot;cachedCues=snapshot.cues;lastObserved=null;skipSamplesUntil=-Infinity;
  lastCompletedDelay=null;makeMonitor();
  monitorObserveFor(current,false);
  lastObserved={...current};
  return state();
}
function resetSeek(snapshot){
  cancelPending("Playback seek discarded speech sample");
  current=snapshot;cachedCues=snapshot.cues;
  if(monitor){monitor.dispose();monitorObserveFor(current,true);}
  else makeMonitor();
  skipSamplesUntil=current.positionSec+defaults.samplePeriodSec;
  lastObserved={...current};
  return state();
}
function updateSnapshot(raw,{observe=false}={}){
  const sameTrack=!!current&&raw?.trackKey===current.trackKey;
  const next=normalize(raw,sameTrack?cachedCues:[]);
  if(!monitor)return {reset:true,state:resetIdentity(next)};
  if(current&&next.trackKey!==current.trackKey)return {reset:true,state:resetIdentity(next)};
  current=next;cachedCues=next.cues;
  if(seeked(lastObserved,next)){
    cancelPending("Playback seek discarded speech sample");
    monitorObserveFor(current,false);
    skipSamplesUntil=current.positionSec+defaults.samplePeriodSec;
    lastObserved={...current};
    return {reset:true,state:state()};
  }
  if(observe){
    const suppress=current.positionSec<skipSamplesUntil;
    monitorObserveFor(current,suppress);
    lastObserved={...current};
  }
  return {reset:false,state:null};
}
function intervalPairs(raw){
  if(!Array.isArray(raw)||raw.length>20000)throw Error("Invalid speech intervals");
  return raw.map((item)=>{
    const a=Array.isArray(item)?item[0]:item?.startSec;
    const b=Array.isArray(item)?item[1]:item?.endSec;
    if(!finite(a)||!finite(b)||b<a)throw Error("Invalid speech interval");
    return [a,b];
  });
}
function applyPending(raw){
  const update=updateSnapshot(raw);
  if(update.reset)return update.state;
  const offer=monitor.pendingOffer;
  if(!offer)return state();
  if(offerBasisDelay!==null&&Math.abs(current.subDelaySec-offerBasisDelay)>defaults.externalDelayEpsSec){
    monitor.dispose();monitorObserveFor(current,true);lastObserved={...current};
    return state();
  }
  const correction=offer?{residualSec:offer.residualSec,stepSec:offer.stepSec,pCorrect:offer.pCorrect}:null;
  capturedDelay=null;
  const applied=monitor.applyPending();
  const appliedDelay=capturedDelay;
  capturedDelay=null;
  if(applied){lastOfferObject=null;offerBasisDelay=null;return state({correction,appliedDelaySec:appliedDelay});}
  return state();
}
function handle(request){
  if(!request||typeof request!="object")throw Error("Invalid request");
  switch(request.operation){
    case "reset":{
      const snapshot=normalize(request.snapshot,request.reason==="seek"?cachedCues:[]);
      return request.reason==="seek"?resetSeek(snapshot):resetIdentity(snapshot);
    }
    case "observe":{
      const update=updateSnapshot(request.snapshot,{observe:true});
      return update.state??state();
    }
    case "completeSpeech":{
      if(request.snapshot)updateSnapshot(request.snapshot);
      const entry=pendingRequests.get(request.requestID);
      if(typeof request.requestID!=="string"||!entry||!request.requestID.startsWith(generation+":"))return state({accepted:false});
      let pairs;
      try{pairs=intervalPairs(request.intervals);}catch(error){pendingRequests.delete(request.requestID);entry.reject(error);throw error;}
      pendingRequests.delete(request.requestID);
      lastCompletedDelay=entry.delayAtStart;
      entry.resolve(pairs);
      return state({accepted:true});
    }
    case "rejectSpeech":{
      if(request.snapshot)updateSnapshot(request.snapshot);
      const entry=pendingRequests.get(request.requestID);
      if(typeof request.requestID!=="string"||!entry||!request.requestID.startsWith(generation+":"))return state({accepted:false});
      pendingRequests.delete(request.requestID);entry.reject(Error("Speech extraction failed"));
      return state({accepted:true});
    }
    case "drain":{
      if(request.snapshot){const update=updateSnapshot(request.snapshot);if(update.reset)return update.state;}
      return state();
    }
    case "applyPending":return applyPending(request.snapshot);
    default:throw Error("Unknown subtitle drift operation");
  }
}
globalThis.harborSubtitleDriftMonitor=(raw)=>handle(JSON.parse(raw));
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
  original_modules: 4,
  pure_monitor_no_tauri_or_io: true,
  program: { source, sha256: crypto.createHash("sha256").update(source).digest("hex") },
};
fs.writeFileSync(
  path.join(repo, "ios/Harbor/SubtitleDriftMonitorAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
console.log(
  JSON.stringify({
    original_modules: 4,
    program_bytes: Buffer.byteLength(source),
    sha256: asset.program.sha256,
    pure_monitor_no_tauri_or_io: true,
  }),
);
