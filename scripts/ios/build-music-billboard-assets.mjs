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
  "billboard-directory": "ea9e2bf0cc8e722b21e2b8b70de2579430052d91cc2e58bf08b61e62bb49641f",
  "discovery-billboard": "e0f95f3a5e1a18d6c1b7e6da958834218b5d8707606e5b692c84821861d63511",
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
  const source = bytes.toString("utf8").replaceAll("\r\n", "\n");
  const { outputText, diagnostics } = ts.transpileModule(source, {
    reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  });
  assert(!diagnostics?.some((entry) => entry.category === ts.DiagnosticCategory.Error));
  modules.push(`${JSON.stringify(name)}:function(require,exports){\n${outputText}\n}`);
  files[file] = digest;
}
const source = `var plugin=(()=>{
  async function response(url,options={},maximum=8*1024*1024){
    const signal=options.signal;
    const value=await new Promise((resolve,reject)=>{
      const abort=()=>reject(new Error("Billboard request aborted"));
      if(signal?.aborted){abort();return;}
      signal?.addEventListener("abort",abort,{once:true});
      harbor.http(String(url),{method:"GET",responseType:"text",timeoutMs:15000})
        .then(value=>{signal?.removeEventListener("abort",abort);resolve(value);},error=>{signal?.removeEventListener("abort",abort);reject(error);});
    });
    const text=String(value.body??""),bytes=new TextEncoder().encode(text);
    if(bytes.byteLength>maximum)throw new Error("Billboard response is too large");
    return {ok:value.ok===true,status:value.status,json:async()=>JSON.parse(text),body:{getReader(){let sent=false;return {
      async read(){if(sent)return {done:true};sent=true;return {done:false,value:bytes};},
      async cancel(){sent=true;},releaseLock(){}
    };}}};
  }
  const factories={${modules.join(",\n")}},instances={};
  function require(name){
    if(name==="@/lib/safe-fetch")return {safeFetch:response,safeFetchBytes:(url,options,timeout,maximum)=>response(url,options,maximum)};
    if(name==="@/lib/debug")return {dwarn(){}};
    if(name==="./catalog")return {searchTyped(){throw new Error("Native album candidates required");}};
    const id=name.startsWith("./")?name.slice(2):name;
    if(instances[id])return instances[id];
    if(!factories[id])throw new Error("Unknown pinned Billboard module");
    const exports={};instances[id]=exports;factories[id](require,exports);return exports;
  }
  const charts=require("billboard-directory").BILLBOARD_CHARTS,board=require("discovery-billboard");
  return {id:"harbor-music-billboard",name:"Harbor Music Billboard",async content(input){
    switch(input.operation){
      case "definitions":return charts;
      case "parse":{const chart=charts.find(value=>value.id===input.chart);if(!chart)throw new Error("Unknown Billboard chart");return board.parseBillboardChart(input.html,chart);}
      case "load":return board.loadBillboardChart(input.chart,undefined,input.refresh===true);
      case "resolve":{
        const isolated={};
        factories["discovery-billboard"](name=>name==="./catalog"?{searchTyped:async()=>({albums:input.albums??[]})}:require(name),isolated);
        return isolated.resolveBillboardItem(input.item);
      }
      default:throw new Error("Unsupported Billboard operation");
    }
  }};
})();`;
const context = vm.createContext({
  harbor: {
    http() {
      throw new Error("Generation cannot access providers");
    },
  },
});
vm.runInContext(source, context);
const charts = JSON.parse(
  JSON.stringify(await context.plugin.content({ operation: "definitions" })),
);
assert(charts.length > 150 && new Set(charts.map((chart) => chart.id)).size === charts.length);
assert(
  charts.every(
    (chart) => /^[a-z0-9-]+$/.test(chart.id) && ["track", "album", "artist"].includes(chart.kind),
  ),
);
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: files,
  charts,
  program: { source, sha256: hash(source) },
};
await writeFile(
  path.join(root, "ios/Harbor/MusicBillboardAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
const labels = new Set([
  "music.row.charts",
  "music.filter.all",
  "music.filter.tracks",
  "music.search.tracks",
  "music.watch.back",
  "music.loading",
  "common.retry",
]);
const view = await readFile(
  path.join(reference, "src/components/music/music-billboard-page.tsx"),
  "utf8",
);
for (const match of view.matchAll(/t\("([^"]+)"/g)) labels.add(match[1]);
await writeFile(
  path.join(root, "ios/Harbor/DesktopMusicBillboardLabels.json"),
  JSON.stringify({ keys: [...labels].sort() }, null, 2) + "\n",
);
await writeFile(
  path.join(root, "docs/ios/music-billboard-sources.json"),
  JSON.stringify(
    {
      reference_version: "0.9.132",
      reference_commit: asset.reference,
      original_inputs: files,
      original_chart_count: charts.length,
      program_sha256: asset.program.sha256,
      preserved: [
        "all original chart identities, groups, countries and kinds",
        "DOM parser with canonical identity and date checks",
        "original rank, artwork host and duplicate validation",
        "8 MiB response budget",
        "one-hour cache with sixteen-chart limit",
        "exact unique album resolution",
        "original measured artist authority and namesake ranking",
      ],
      generator_accesses_providers: false,
      generator_executes_apple_tests: false,
      full_music_parity_complete: false,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  `Original Billboard: ${charts.length} charts, six preserved modules, SHA256 ${asset.program.sha256}`,
);
