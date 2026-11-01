import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import ts from "typescript";

const reference = "0834340cec5531650bfe78cd628628702e636987";
const file = "src/lib/music/lyrics.ts";
const original = execFileSync("git", ["show", `${reference}:${file}`]);
const digest = (data) => createHash("sha256").update(data).digest("hex");
const compiled = ts.transpileModule(original.toString("utf8"), {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
}).outputText;
const source = `var plugin=(()=>{
  const exports={};
  const safeFetch=async(url,opts={})=>{
    const response=await harbor.http(String(url),{method:"GET",responseType:"text",timeoutMs:12000,headers:opts.headers??{}});
    return {ok:response.ok===true,json:async()=>JSON.parse(String(response.body??"null"))};
  };
  const require=name=>{if(name==="@/lib/safe-fetch")return{safeFetch};throw new Error("Unknown lyrics dependency");};
  ${compiled}
  return {id:"harbor-music-lyrics",name:"Harbor Music Lyrics",content(input){
    switch(input.operation){
      case "load":return exports.loadTrackLyrics(input.track);
      case "parse":return exports.parseLrc(input.lrc);
      case "index":return exports.lyricIndexAt(input.lines,input.position);
      default:throw new Error("Unknown lyrics operation");
    }
  }};
})();`;
writeFileSync(
  "ios/Harbor/MusicLyricsAssets.json",
  JSON.stringify(
    {
      schema: 1,
      reference,
      inputs: { [file]: digest(original) },
      program: { source, sha256: digest(source) },
    },
    null,
    2,
  ) + "\n",
);
console.log(`Original lyrics module: ${digest(original)}; native program: ${digest(source)}`);
