import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const option = process.argv.indexOf("--reference");
assert(option >= 0 && process.argv[option + 1]);
const reference = path.resolve(process.argv[option + 1]);
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const inputs = {
  "genre-catalog": "6eb5559ccf2a8d1f1378f1fb105cbe9b45a6bd5328083e5962663fae75277a2a",
  "genre-artist-roster": "c379ad5a13089ad94cf66f6e006fffe2d61f59fe1a272cefd6e451548e521f11",
  "recording-profile": "df5a5b40d65999dbde38b5dd5b17c43166c71f32806b16184a521548c933cf45",
  "genre-insights": "c03df7889ceeac1b39557ae0d7b9475cb3d3682750d5eb0e0940da0396d93af9",
  "artist-authority": "22c9a4c64f39b2fc30afadd8ad0efad77e854d22369a83f0d15b1e9d3ebf1688",
  "artist-popularity": "7d95c390711282cfd95062774305d475a8151c1e0a627d220de4baea7c3a94cc",
  "search-normalize": "972d5f2778059adf59ee6d72a6c7f45012f371e93f3dac8dfa0dff2de7aac029",
  "@/lib/cache": "8e7016f707a788993b5d9e6763c03c26e318987a3fb91b905f8fbbdbb4fd9171",
};
const modules = [],
  files = {};
for (const [name, digest] of Object.entries(inputs)) {
  const file = name.startsWith("@/") ? `src/${name.slice(2)}.ts` : `src/lib/music/${name}.ts`;
  const bytes = await readFile(path.join(reference, file));
  assert.equal(hash(bytes), digest, file);
  const { outputText, diagnostics } = ts.transpileModule(
    bytes.toString("utf8").replaceAll("\r\n", "\n"),
    {
      reportDiagnostics: true,
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
    },
  );
  assert(!diagnostics?.some((entry) => entry.category === ts.DiagnosticCategory.Error));
  modules.push(`${JSON.stringify(name)}:function(require,exports){\n${outputText}\n}`);
  files[file] = digest;
}
const lastfm = await readFile(path.join(reference, "src/lib/music/lastfm.ts"));
assert.equal(hash(lastfm), "7d057374ff6796cac84df6c10878fa1bed16098ffa713b7d3a004735f51fd279");
const keyName = lastfm.toString("utf8").match(/export const LASTFM_API_KEY = "([^"]+)";/)?.[1];
assert.equal(keyName, "harbor.lastfm.v1.apiKey");
files["src/lib/music/lastfm.ts"] = hash(lastfm);
const source = `var plugin=(()=>{
  const __APP_VERSION__="0.9.132";
  const AbortSignal={timeout(ms){const controller=new AbortController();setTimeout(()=>controller.abort(),ms);return controller.signal;}};
  async function safeFetch(url,options={}){
    const signal=options.signal;
    const value=await new Promise((resolve,reject)=>{
      const abort=()=>reject(new Error("Artist metadata request aborted"));
      if(signal?.aborted){abort();return;}
      signal?.addEventListener("abort",abort,{once:true});
      harbor.http(String(url),{method:"GET",responseType:"text",timeoutMs:12000,headers:options.headers??{}})
        .then(value=>{signal?.removeEventListener("abort",abort);resolve(value);},error=>{signal?.removeEventListener("abort",abort);reject(error);});
    });
    const text=String(value.body??""),bytes=new TextEncoder().encode(text);let sent=false;
    return {ok:value.ok===true,status:value.status,json:async()=>JSON.parse(text),headers:{get(name){return Object.entries(value.headers??{}).find(([key])=>key.toLowerCase()===String(name).toLowerCase())?.[1]??null;}},
      body:{async cancel(){sent=true;},getReader(){return {async read(){if(sent)return {done:true};sent=true;return {done:false,value:bytes};},async cancel(){sent=true;},releaseLock(){}};}}};
  }
  const factories={${modules.join(",\n")}};
  function create(apiKey){
    const instances={};
    function require(name){
      if(name==="@/lib/safe-fetch")return {safeFetch};
      if(name==="@/lib/debug")return {dwarn(){}};
      if(name==="@/lib/secret-store")return {loadSecrets:async()=>{},getSecret:key=>key===${JSON.stringify(keyName)}?apiKey:null};
      if(name==="./lastfm")return {LASTFM_API_KEY:${JSON.stringify(keyName)}};
      const id=name.startsWith("./")?name.slice(2):name;
      if(instances[id])return instances[id];
      if(!factories[id])throw new Error("Unknown pinned artist module");
      const exports={};instances[id]=exports;factories[id](require,exports);return exports;
    }
    const recordings=new Map();
    return {async content(input){switch(input.operation){
      case "definitions":return require("genre-catalog").MUSIC_GENRES;
      case "roster":return require("genre-artist-roster").loadGenreArtistRoster(input.genre,input.offset??0);
      case "stats":return require("genre-insights").loadGenreArtistStats(input.artists??[]);
      case "recording":{
        const controller=new AbortController();recordings.set(input.requestId,controller);
        try{return await require("recording-profile").loadRecordingProfile(input.track,controller.signal);}
        finally{recordings.delete(input.requestId);}
      }
      case "cancelRecording":recordings.get(input.requestId)?.abort();return null;
      case "parseRecording":return require("recording-profile").parseDeezerRecording(input.recording,input.id,input.match??"provider-id");
      case "resolve":return require("artist-authority").resolveArtist(input.name,input.options??{});
      default:throw new Error("Unsupported artist metadata operation");
    }}};
  }
  let engine=null;
  return {id:"harbor-music-artists",name:"Harbor Music Artists",content(input){engine??=create(input.apiKey??null);return engine.content(input);}};
})();`;
const context = vm.createContext({
  harbor: {
    http() {
      throw new Error("Generation cannot contact providers");
    },
  },
});
vm.runInContext(source, context);
const definitions = await context.plugin.content({ operation: "definitions" });
assert.equal(definitions.length, 159);
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: files,
  program: { source, sha256: hash(source) },
};
await writeFile(
  path.join(root, "ios/Harbor/MusicArtistAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
const labels = new Set([
  "music.explore.sceneArtists",
  "music.explore.listeners",
  "music.explore.scrobbles",
  "music.metadata.deezerFans",
  "music.library.loadMore",
  "music.credits.title",
  "Metadata",
  "API key",
  "Save",
  "Saved",
  "Remove",
  "Removed",
  "Loading",
  "Retry",
  "Done",
  "music.error.load",
  "music.lastfm.apiKey",
  "Get an API key",
]);
for (const role of ["main", "featured", "composer", "lyricist", "producer", "performer"])
  labels.add("music.credits." + role);
await writeFile(
  path.join(root, "ios/Harbor/DesktopMusicArtistLabels.json"),
  JSON.stringify({ keys: [...labels].sort() }, null, 2) + "\n",
);
await writeFile(
  path.join(root, "docs/ios/music-artist-sources.json"),
  JSON.stringify(
    {
      reference_version: "0.9.132",
      reference_commit: asset.reference,
      original_inputs: files,
      program_sha256: asset.program.sha256,
      original_modules: 8,
      public_secret_key_identifier_only: keyName,
      preserved: [
        "24-artist original tagged MusicBrainz roster and original returned-row cursor",
        "MusicBrainz 1100ms scheduling and bounded metadata queue",
        "30-minute roster and statistics cache",
        "original authority and namesake resolution",
        "three-at-a-time original statistics enrichment",
        "original recording identity/ISRC/title-credit matching and attributed credits",
        "recording consumer coalescing and source-specific cache TTLs",
      ],
      generator_accesses_providers: false,
      generator_executes_apple_tests: false,
      contains_personal_api_key: false,
      full_music_parity_complete: false,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  `Original artist metadata: eight modules and public Last.fm key identifier, SHA256 ${asset.program.sha256}`,
);
