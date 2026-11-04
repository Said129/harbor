import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

// Pins the original Desktop 0.9.132 debrid clients (Real-Debrid, TorBox,
// AllDebrid, Premiumize and Debrid-Link) and the episode-file matcher by SHA-256,
// runs them unchanged behind a small operation facade and a host HTTP shim, and
// records a Node evaluation of the Real-Debrid flow as the native expectation.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const option = process.argv.indexOf("--reference");
assert(option >= 0 && process.argv[option + 1]);
const reference = path.resolve(process.argv[option + 1]);
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const inputs = {
  "src/lib/debrid/types.ts": [
    "types",
    "282aab5e288e976a5a5fd582cea636c3e615411ae11205db16391e08276db693",
  ],
  "src/lib/debrid/realdebrid.ts": [
    "realdebrid",
    "7dde8ef0d27f6cef7c9f4f4a89cf049acd81cf24ac5e936f6cf256dc462bff0b",
  ],
  "src/lib/debrid/alldebrid.ts": [
    "alldebrid",
    "1e8bca2323909387f377b4400ad59db927cff3709a4cb681873d7218994f7adf",
  ],
  "src/lib/debrid/debridlink.ts": [
    "debridlink",
    "3fcc341261b286ea32518f1e6ee4642445dd968d68affcb8b36c2650232d82ff",
  ],
  "src/lib/debrid/premiumize.ts": [
    "premiumize",
    "52dd5e43df7ff38e02a048a17b93e657537c5587db0291f85d91c1dedd886aa1",
  ],
  "src/lib/debrid/torbox.ts": [
    "torbox",
    "11e01d9fd8c35bea1b14f4422f643a79cda127501e300d4936c5981b75554234",
  ],
  "src/lib/streams/episode-file.ts": [
    "episode-file",
    "50e1b68e04b469a8558745fce1bb8b3537a2840ea66fb17bb370a981c0a8c276",
  ],
  "src/lib/episode-span.ts": [
    "episode-span",
    "f7431cfa9f39f35fd217e2a46982871c8eac90ae2442bdf64a0d8f200c9488ef",
  ],
};
const modules = [],
  files = {};
for (const [file, [name, digest]] of Object.entries(inputs)) {
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
const source = `var plugin=(()=>{
  async function safeFetch(url,options={}){
    const signal=options.signal;
    const value=await new Promise((resolve,reject)=>{
      const abort=()=>{const error=new Error("Debrid request aborted");error.name="AbortError";reject(error);};
      if(signal?.aborted){abort();return;}
      signal?.addEventListener("abort",abort,{once:true});
      harbor.http(String(url),{method:options.method??"GET",responseType:"text",timeoutMs:20000,headers:options.headers??{},body:options.body})
        .then(result=>{signal?.removeEventListener("abort",abort);resolve(result);},error=>{signal?.removeEventListener("abort",abort);reject(error);});
    });
    const text=String(value.body??"");
    return {ok:value.ok===true,status:value.status,url:value.url,
      headers:{get(name){return Object.entries(value.headers??{}).find(([key])=>key.toLowerCase()===String(name).toLowerCase())?.[1]??null;}},
      json:async()=>JSON.parse(text),text:async()=>text};
  }
  const factories={${modules.join(",\n")}};
  const instances={};
  function require(name){
    if(name==="@/lib/safe-fetch")return {safeFetch};
    // Desktop logs only in development builds; the native host keeps no debrid logs.
    if(name==="@/lib/debug")return {dlog(){},dinfo(){},dwarn(){}};
    const id={"./types":"types","@/lib/streams/episode-file":"episode-file","@/lib/episode-span":"episode-span"}[name]??name.replace(/^\\.\\//,"");
    if(instances[id])return instances[id];
    if(!factories[id])throw new Error("Unknown pinned debrid module");
    const exports={};instances[id]=exports;factories[id](require,exports);return exports;
  }
  const makers={rd:["realdebrid","createRealDebrid"],tb:["torbox","createTorbox"],ad:["alldebrid","createAllDebrid"],pm:["premiumize","createPremiumize"],dl:["debridlink","createDebridLink"]};
  function store(input){
    const maker=makers[input.slug];
    if(!maker||typeof input.key!=="string"||!input.key)throw new Error("Unsupported debrid provider");
    return require(maker[0])[maker[1]](input.key);
  }
  const requests=new Map();
  async function run(input,body){
    const controller=new AbortController();requests.set(input.requestId,controller);
    try{return await body(controller.signal);}finally{requests.delete(input.requestId);}
  }
  return {id:"harbor-debrid",name:"Harbor Debrid",async content(input){switch(input.operation){
    case "account":return run(input,signal=>store(input).account(signal));
    case "cacheCheck":return run(input,signal=>store(input).cacheCheck(input.hashes??[],signal));
    case "playableUrl":return run(input,signal=>store(input).playableUrl(input.magnet,input.fileIdx??undefined,signal,input.hint??undefined));
    case "queueCache":return run(input,signal=>{const target=store(input);return target.queueCache?target.queueCache(input.magnet,signal):{ok:false,code:"unsupported",status:0};});
    case "listLibrary":return run(input,signal=>store(input).listLibrary(signal));
    case "cancel":requests.get(input.requestId)?.abort();return null;
    default:throw new Error("Unsupported debrid operation");
  }}};
})();`;

// Independent evaluation: the original Real-Debrid client over owned responses.
const KEY = "owned-rd-key";
const HASH = "aabbccddeeff00112233445566778899aabbccdd";
const BASE = "https://api.real-debrid.com/rest/1.0";
const script = {
  [`GET ${BASE}/user`]: [
    {
      status: 200,
      body: {
        username: "owned",
        email: "owned@example.invalid",
        premium: 1,
        expiration: "2030-01-01T00:00:00.000Z",
      },
    },
  ],
  [`POST ${BASE}/torrents/addMagnet`]: [{ status: 201, body: { id: "RD1" } }],
  [`GET ${BASE}/torrents/info/RD1`]: [
    {
      status: 200,
      body: {
        id: "RD1",
        status: "waiting_files_selection",
        progress: 0,
        files: [
          { id: 1, path: "/Owned.Show.S01E01.mkv", bytes: 1000, selected: 0 },
          { id: 2, path: "/readme.nfo", bytes: 1, selected: 0 },
        ],
        links: [],
      },
    },
    {
      status: 200,
      body: {
        id: "RD1",
        status: "downloaded",
        progress: 100,
        files: [
          { id: 1, path: "/Owned.Show.S01E01.mkv", bytes: 1000, selected: 1 },
          { id: 2, path: "/readme.nfo", bytes: 1, selected: 0 },
        ],
        links: ["https://real-debrid.com/d/OWNED"],
      },
    },
  ],
  [`POST ${BASE}/torrents/selectFiles/RD1`]: [{ status: 204, body: null }],
  [`POST ${BASE}/unrestrict/link`]: [
    {
      status: 200,
      body: {
        download: "https://cdn.owned.example/Owned.Show.S01E01.mkv",
        filename: "Owned.Show.S01E01.mkv",
        filesize: 1000,
      },
    },
  ],
};
const observed = [];
function runtime(table) {
  const queue = Object.fromEntries(Object.entries(table).map(([key, value]) => [key, [...value]]));
  const context = vm.createContext({
    URL,
    URLSearchParams,
    AbortController,
    TextEncoder,
    setTimeout,
    clearTimeout,
    Date,
    harbor: {
      async http(url, options = {}) {
        const method = options.method ?? "GET";
        observed.push({
          method,
          url,
          body: options.body ?? null,
          bearer: options.headers?.Authorization === `Bearer ${KEY}`,
        });
        const next = queue[`${method} ${url}`]?.shift();
        assert(next, `Unexpected request ${method} ${url}`);
        return {
          ok: next.status >= 200 && next.status < 300,
          status: next.status,
          headers: {},
          body: next.body === null ? "" : JSON.stringify(next.body),
          url,
        };
      },
    },
  });
  vm.runInContext(source, context);
  return (input) => context.plugin.content(input);
}
// Results cross a vm context boundary: compare plain data, not foreign prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value));
const call = runtime(script);
const account = plain(await call({ operation: "account", slug: "rd", key: KEY, requestId: "a" }));
const playable = plain(
  await call({
    operation: "playableUrl",
    slug: "rd",
    key: KEY,
    magnet: HASH,
    requestId: "p",
    hint: { season: 1, episode: 1 },
  }),
);
const forbiddenScript = { [`GET ${BASE}/user`]: [{ status: 401, body: { error: "bad_token" } }] };
const forbidden = runtime(forbiddenScript);
const unauthorized = plain(
  await forbidden({ operation: "account", slug: "rd", key: KEY, requestId: "u" }),
);
const uncachedScript = {
  [`POST ${BASE}/torrents/addMagnet`]: [{ status: 201, body: { id: "RD2" } }],
  [`GET ${BASE}/torrents/info/RD2`]: [
    { status: 200, body: { id: "RD2", status: "downloading", progress: 12, files: [], links: [] } },
  ],
  [`DELETE ${BASE}/torrents/delete/RD2`]: [{ status: 204, body: null }],
};
const uncached = runtime(uncachedScript);
const notCached = plain(
  await uncached({ operation: "playableUrl", slug: "rd", key: KEY, magnet: HASH, requestId: "n" }),
);
await assert.rejects(
  call({ operation: "account", slug: "zz", key: KEY, requestId: "z" }),
  /Unsupported debrid provider/,
);
await assert.rejects(
  call({ operation: "account", slug: "rd", key: "", requestId: "z" }),
  /Unsupported debrid provider/,
);
assert.deepEqual(account, {
  ok: true,
  data: {
    slug: "rd",
    username: "owned",
    email: "owned@example.invalid",
    premium: true,
    premiumUntil: 1893456000,
  },
});
assert.equal(playable.ok, true);
assert.equal(playable.data.url, "https://cdn.owned.example/Owned.Show.S01E01.mkv");
assert.equal(unauthorized.ok, false);
assert.equal(unauthorized.code, "unauthorized");
assert.equal(notCached.code, "not-cached");
assert(
  observed.every((entry) => entry.bearer),
  "The key is sent only as a bearer header",
);
assert(observed.every((entry) => entry.url.startsWith("https://api.real-debrid.com/")));
const selectBody = observed.find((entry) => entry.url.endsWith("/selectFiles/RD1"))?.body;
assert.equal(selectBody, "files=1", "Only the matched video file is selected");

const digest = hash(source);
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: files,
  program: { source, sha256: digest },
};
await writeFile(
  path.join(root, "ios/Harbor/DebridAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
await writeFile(
  path.join(root, "ios/HarborTests/Fixtures/debrid-reference.json"),
  JSON.stringify(
    {
      schema: 1,
      reference: asset.reference,
      program_sha256: digest,
      key: KEY,
      hash: HASH,
      account,
      playable,
      unauthorized_code: unauthorized.code,
      not_cached_code: notCached.code,
      scripts: { flow: script, forbidden: forbiddenScript, uncached: uncachedScript },
      requests: observed.map(({ method, url, body }) => ({ method, url, body })),
    },
    null,
    2,
  ) + "\n",
);
await writeFile(
  path.join(root, "docs/ios/debrid-sources.json"),
  JSON.stringify(
    {
      reference_version: "0.9.132",
      reference_commit: asset.reference,
      original_inputs: files,
      program_sha256: digest,
      original_modules: Object.keys(inputs).length,
      providers: ["rd", "tb", "ad", "pm", "dl"],
      preserved: [
        "Real-Debrid, TorBox, AllDebrid, Premiumize and Debrid-Link account, cache, playable URL, queue and library calls",
        "episode-file matching so a season pack opens the requested episode",
        "original result codes: unauthorized, not-premium, rate-limited, not-cached and the rest",
      ],
      host_shims: ["safe-fetch over the native HTTP transport", "debug (no logging)"],
      not_ported_yet: [
        "stream pipeline cache verification",
        "library lookup in the stream list",
        "prepared-link prefetch",
        "play-time resolution",
      ],
      generator_accesses_providers: false,
      contains_personal_api_key: false,
    },
    null,
    2,
  ) + "\n",
);
console.log(`Original debrid clients: ${Object.keys(inputs).length} modules, SHA256 ${digest}`);
console.log(`Real-Debrid flow: ${observed.length} requests, playable ${playable.data.url}`);
