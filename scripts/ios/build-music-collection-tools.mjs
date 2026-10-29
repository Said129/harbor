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
const inputs = {},
  programs = {};
const sha = (value) => crypto.createHash("sha256").update(value).digest("hex");
for (const name of [
  "playlist-filters",
  "source-label",
  "track-identity",
  "search-normalize",
  "search-artists",
]) {
  const file = "src/lib/music/" + name + ".ts";
  const checkout = fs.readFileSync(path.join(reference, file));
  const original = execFileSync("git", ["show", revision + ":" + file], { cwd: repo });
  if (
    checkout.toString("utf8").replace(/\r\n/g, "\n") !==
    original.toString("utf8").replace(/\r\n/g, "\n")
  )
    throw Error("Changed collection source " + file);
  inputs[file] = { checkout_sha256: sha(checkout), committed_sha256: sha(original) };
  let source = original.toString("utf8");
  if (name === "search-artists") {
    const tree = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
    const declaration = tree.statements
      .filter(ts.isVariableStatement)
      .flatMap((node) => node.declarationList.declarations)
      .find((node) => node.name.getText(tree) === "artistCreditParts");
    if (!declaration) throw Error("Original artist credit split unavailable");
    source = "export const artistCreditParts=" + declaration.initializer.getText(tree) + ";";
  }
  programs["./" + name] = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
}
const program = `(function(){"use strict";
const programs=${JSON.stringify(programs)},cache={};
function require(name){if(cache[name])return cache[name];if(!programs[name])throw Error("Unsupported collection module");const exports={};cache[name]=exports;new Function("exports","require",programs[name])(exports,require);return exports;}
const filters=require("./playlist-filters"),identity=require("./track-identity"),labels=require("./source-label");
globalThis.harborMusicCollectionTools=function(raw){
 const input=JSON.parse(raw),tracks=input.tracks??[];
 if(!Array.isArray(tracks)||tracks.length>10000)throw Error("Invalid collection");
 let result;
 switch(input.operation){
 case "filter":{
  const f={...filters.DEFAULT_PLAYLIST_FILTERS,...input.filters};
  if(!["default","added","title","artist","album","duration"].includes(f.sort)||!["all","clean","explicit"].includes(f.content)||!["list","compact"].includes(f.view)||typeof f.query!=="string"||f.query.length>200)throw Error("Invalid collection filters");
  const metadata={...input.metadata};
  if(input.genreTracks)metadata.genreTracks=new Map(Object.entries(input.genreTracks).map(([id,ids])=>[Number(id),new Set(ids)]));
  result=filters.filterPlaylist(tracks,f,metadata);break;
 }
 case "sources":result=[...new Set(tracks.map(filters.playlistSource))].filter(Boolean);break;
 case "label":result=labels.sourceLabel(input.source??"");break;
 case "identity":result=identity.musicTrackIdentity(input.track);break;
 case "addable":{
  const held=new Set(tracks.map(identity.musicTrackIdentity));
  result=identity.dedupeMusicTracks(input.candidates??[]).filter(track=>!held.has(identity.musicTrackIdentity(track)));break;
 }
 default:throw Error("Unknown collection operation");
 }
 return JSON.stringify(result);
};})();\n`;
const asset = {
  schema: 1,
  reference: revision,
  inputs,
  complete_original_modules: [
    "playlist-filters",
    "source-label",
    "track-identity",
    "search-normalize",
  ],
  selected_original_functions: ["search-artists.artistCreditParts"],
  program: { source: program, sha256: sha(program), bytes: Buffer.byteLength(program) },
};
fs.writeFileSync(
  path.join(repo, "ios/Harbor/MusicCollectionToolsAssets.json"),
  JSON.stringify(asset, null, 2) + "\n",
);
process.stdout.write(
  JSON.stringify({
    modules: 4,
    selected_functions: 1,
    bytes: asset.program.bytes,
    sha256: asset.program.sha256,
  }) + "\n",
);
