import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const index = process.argv.indexOf("--reference");
assert(index >= 0 && process.argv[index + 1]);
const reference = path.resolve(process.argv[index + 1]);
const hash = (value) => createHash("sha256").update(value).digest("hex");
const inputs = {
  "genre-catalog": "6eb5559ccf2a8d1f1378f1fb105cbe9b45a6bd5328083e5962663fae75277a2a",
  "genre-artwork": "fd08d0d6ed4ea2cb61c80fe6b6feaf831366a302f00b6c70cbfd00470c853144",
  "genre-editorial": "91644a9e77986fbfbe36d418e400bde0f87f2bebb01eb5abd6acccb41db2ae3f",
  "genre-editorial-loader": "815840c002d6fe8ac82b6e1014421fe695580679c6ae64fdcd88f7e0b33a7d71",
  "genre-playlist-pool": "1162fc94fe09c5d90264e32b21a0623888c02e0b5fc76bdd5a78fe6664a52b0c",
  discovery: "6f974f6c5f2670bdb2b756b3232752ed9ce10dc479eedeceb704f5d1e8a74d54",
};
const modules = [];
for (const [name, digest] of Object.entries(inputs)) {
  const file = `src/lib/music/${name}.ts`;
  const bytes = await readFile(path.join(reference, file));
  assert.equal(hash(bytes), digest, file);
  const source = bytes.toString("utf8").replaceAll("\r\n", "\n");
  const tree = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
  assert.equal(tree.parseDiagnostics.length, 0, file);
  const { outputText, diagnostics } = ts.transpileModule(source, {
    reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  });
  assert(!diagnostics?.some((value) => value.category === ts.DiagnosticCategory.Error));
  modules.push(`${JSON.stringify(name)}:function(require,exports){\n${outputText}\n}`);
}
const source = `var plugin=(()=>{
  const AbortSignal={timeout(ms){const controller=new AbortController();setTimeout(()=>controller.abort(),ms);return controller.signal;}};
  async function safeFetch(url,options={}){
    const signal=options.signal;
    const value=await new Promise((resolve,reject)=>{
      const abort=()=>reject(new Error("Music discovery request aborted"));
      if(signal?.aborted){abort();return;}
      signal?.addEventListener("abort",abort,{once:true});
      harbor.http(String(url),{method:"GET",responseType:"text",timeoutMs:15000})
        .then(value=>{signal?.removeEventListener("abort",abort);resolve(value);},error=>{signal?.removeEventListener("abort",abort);reject(error);});
    });
    return {ok:value.ok===true,status:value.status,json:async()=>JSON.parse(String(value.body??""))};
  }
  const factories={${modules.join(",\n")}},instances={};
  function require(name){
    if(name==="@/lib/safe-fetch")return {safeFetch};
    const id=name.startsWith("./")?name.slice(2):name;
    if(instances[id])return instances[id];
    if(!factories[id])throw new Error("Unknown pinned discovery module");
    const exports={};instances[id]=exports;factories[id](require,exports);return exports;
  }
  const catalog=require("genre-catalog"),art=require("genre-artwork"),discovery=require("discovery");
  return {id:"harbor-music-explore",name:"Harbor Music Explore",async content(input){
    switch(input.operation){
      case "definitions":return {genres:catalog.MUSIC_GENRES,artwork:art.MUSIC_GENRE_ARTWORK,countries:catalog.MUSIC_GENRE_COUNTRIES,families:catalog.MUSIC_GENRE_FAMILIES,editorialScenes:Object.keys(require("genre-editorial").EDITORIAL_SCENES),playlistScenes:catalog.MUSIC_GENRES.filter(value=>require("genre-playlist-pool").isPlaylistScene(value.slug)).map(value=>value.slug)};
      case "filter":return catalog.filterMusicGenres(catalog.MUSIC_GENRES,input.query??"",input.countries??[],input.family??"",code=>input.countryNames?.[code]??code,genre=>catalog.musicGenreName(genre,key=>input.genreNames?.[key]??key));
      case "related":return catalog.relatedMusicGenres(catalog.musicGenre(input.genre));
      case "chart":return {...await discovery.loadMusicDiscoveryChart(),playlists:[]};
      case "selection":return discovery.loadMusicGenreSelection(input.genre);
      case "tracks":return discovery.loadMusicGenreTracksPage(input.genre,input.page);
      case "artists":return discovery.loadMusicGenreArtistsPage(input.genre,input.page);
      case "playlists":return discovery.loadMusicDiscoveryPlaylists(input.genre??0,input.limit??24);
      default:throw new Error("Unsupported native discovery operation");
    }
  }};
})();`;
const sandbox = vm.createContext({
  URL,
  AbortSignal,
  harbor: {
    http() {
      throw new Error("Generation must not access providers");
    },
  },
});
vm.runInContext(source, sandbox);
const definitions = JSON.parse(
  JSON.stringify(await sandbox.plugin.content({ operation: "definitions" })),
);
assert.equal(new Set(definitions.genres.map((value) => value.id)).size, definitions.genres.length);
assert(definitions.genres.length > 100 && definitions.families.length === 8);
assert(definitions.genres.every((value) => definitions.artwork[value.id]?.startsWith("https://")));
const excluded = [95];
const labels = new Set([
  "music.discover",
  "music.row.charts",
  "music.artist.popular",
  "music.artist.albums",
  "music.artist.artists",
  "music.search.playlists",
]);
const translations = await readFile(
  path.join(reference, "src/lib/i18n/locales/en/music-taste.ts"),
  "utf8",
);
for (const match of translations.matchAll(/"(music\.(?:explore|genre|taste)\.[^"]+)"\s*:/g))
  labels.add(match[1]);
for (const name of [
  "music-genre-browser",
  "music-genres",
  "music-genre-deep",
  "music-genre-artists",
]) {
  const view = await readFile(path.join(reference, `src/views/music/${name}.tsx`), "utf8");
  for (const match of view.matchAll(/t\("([^"]+)"/g)) labels.add(match[1]);
}
definitions.genres
  .filter((value) => value.id >= 10108 && value.id <= 10133)
  .forEach((value) => labels.add(`music.genre.${value.slug}`));
definitions.families.forEach((value) => labels.add(`music.explore.family.${value}`));
const iconWrapper = "src/components/music/music-discovery-icon.tsx";
const iconSource = await readFile(path.join(reference, iconWrapper), "utf8");
const iconTree = ts.createSourceFile(
  iconWrapper,
  iconSource,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TSX,
);
const imports = new Map(
  [...iconSource.matchAll(/import (\w+) from "@\/(assets\/music-genres\/[^"?]+)\?raw";/g)].map(
    (match) => [match[1], `src/${match[2]}`],
  ),
);
const drawing = iconTree.statements
  .flatMap((node) => (ts.isVariableStatement(node) ? [...node.declarationList.declarations] : []))
  .find((node) => node.name.getText(iconTree) === "drawings");
assert(drawing && ts.isObjectLiteralExpression(drawing.initializer));
const drawings = new Map(
  drawing.initializer.properties.map((node) => [
    Number(node.name.getText(iconTree)),
    imports.get(node.initializer.getText(iconTree)),
  ]),
);
const vectorInputs = { [iconWrapper]: hash(await readFile(path.join(reference, iconWrapper))) };
const vectorOutputs = {};
for (const genre of definitions.genres.filter((value) => !excluded.includes(value.id))) {
  const file = drawings.get(genre.id);
  assert(file, `Missing original genre drawing ${genre.id}`);
  const original = await readFile(path.join(reference, file));
  vectorInputs[file] = hash(original);
  const geometry = original
    .toString("utf8")
    .replaceAll("\r\n", "\n")
    .match(/<svg\b[^>]*>([\s\S]*)<\/svg>\s*$/)?.[1];
  assert(geometry && !/<(?:script|foreignObject|image|use)\b/i.test(geometry));
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" fill="none" stroke="#ffffff">${geometry.replaceAll("currentColor", "#ffffff")}</svg>\n`;
  const target = path.join(root, `ios/Harbor/Assets.xcassets/music-genre-${genre.id}.imageset`);
  await mkdir(target, { recursive: true });
  await writeFile(path.join(target, "icon.svg"), svg);
  await writeFile(
    path.join(target, "Contents.json"),
    JSON.stringify(
      {
        images: [{ idiom: "universal", filename: "icon.svg" }],
        info: { version: 1, author: "xcode" },
        properties: {
          "preserves-vector-representation": true,
          "template-rendering-intent": "template",
        },
      },
      null,
      2,
    ) + "\n",
  );
  vectorOutputs[genre.id] = hash(svg);
}
const asset = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: Object.fromEntries(
    Object.entries(inputs).map(([name, digest]) => [`src/lib/music/${name}.ts`, digest]),
  ),
  definitions,
  mobileExcludedGenreIds: excluded,
  program: { source, sha256: hash(source) },
};
await writeFile(
  path.join(root, "ios/Harbor/MusicExploreAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
await writeFile(
  path.join(root, "ios/Harbor/DesktopMusicExploreLabels.json"),
  JSON.stringify({ keys: [...labels].sort() }, null, 2) + "\n",
);
await writeFile(
  path.join(root, "docs/ios/music-explore-sources.json"),
  JSON.stringify(
    {
      reference_version: "0.9.132",
      reference_commit: asset.reference,
      original_inputs: asset.inputs,
      original_genres: definitions.genres.length,
      visible_mobile_genres: definitions.genres.length - excluded.length,
      genre_families: definitions.families,
      program_sha256: asset.program.sha256,
      preserved: [
        "original genre identities, aliases, country tags and artwork",
        "original matching and editorial membership",
        "three concurrent scene searches",
        "15-minute request cache and pending coalescing",
        "original playlist pool and depth/artist pagination",
      ],
      mobile_excluded_genre_ids: excluded,
      generator_accesses_providers: false,
      generator_executes_apple_tests: false,
      original_vector_inputs: vectorInputs,
      native_vector_outputs: vectorOutputs,
      full_explore_parity_complete: false,
      full_music_parity_complete: false,
    },
    null,
    2,
  ) + "\n",
);
console.log(
  `Original Explore: ${definitions.genres.length} genres, six source modules; native execution still pending. SHA256 ${asset.program.sha256}`,
);
