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
const name = "src/lib/music/queue-order.ts";
const checkout = fs.readFileSync(path.join(reference, name));
const committed = execFileSync("git", ["show", revision + ":" + name], { cwd: repo });
if (
  checkout.toString("utf8").replace(/\r\n/g, "\n") !==
  committed.toString("utf8").replace(/\r\n/g, "\n")
)
  throw Error("Changed original music queue source");
const ts = createRequire(path.join(repo, "package.json"))("typescript");
const compiled = ts.transpileModule(committed.toString("utf8"), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const source = `(function(){"use strict"; const exports={};\n${compiled}
let order=new exports.MusicQueueOrder();
globalThis.harborMusicQueueOrder=function(raw){
 const input=JSON.parse(raw),queue=input.queue??[],index=input.index??-1;
 if(!Array.isArray(queue)||queue.length>500)throw Error("Invalid music queue");
 const modes={shuffle:input.shuffle===true,repeat:input.repeatMode??"off"};
 if(!["off","all","one"].includes(modes.repeat))throw Error("Invalid repeat mode");
 let offset=0;const random=()=>{const value=input.randoms?.[offset++];return typeof value==="number"&&Number.isFinite(value)&&value>=0&&value<1?value:Math.random();};
 let result;
 switch(input.operation){
 case "reset":order.reset();result=true;break;
 case "key":result=exports.queueTrackKey(input.track);break;
 case "next":result=order.next(queue,index,modes,input.automatic===true,input.priority??null,random);break;
 case "previous":result=order.previous(queue,index,modes.shuffle);break;
 case "peekPrevious":result=order.peekPrevious(queue,index,modes.shuffle);break;
 case "upcoming":result=order.upcoming(queue,index,modes,Math.max(0,Math.min(500,input.count??0)),random);break;
 default:throw Error("Unknown music queue operation");
 }
 return JSON.stringify(result??null);
};})();\n`;
const sha = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const asset = {
  schema: 1,
  reference: revision,
  inputs: { [name]: { checkout_sha256: sha(checkout), committed_sha256: sha(committed) } },
  original_class_compiled_complete: true,
  program: { source, sha256: sha(source), bytes: Buffer.byteLength(source) },
};
fs.writeFileSync(
  path.join(repo, "ios/Harbor/MusicQueueOrderAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
process.stdout.write(
  JSON.stringify({
    original_modules: 1,
    bytes: asset.program.bytes,
    sha256: asset.program.sha256,
  }) + "\n",
);
