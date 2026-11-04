import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

// Evaluates the pinned original artist-profile module (inside the bundled
// artist program) against owned MusicBrainz, Wikidata and Wikipedia responses
// and records its outputs as the independent expectation for the native test.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const asset = JSON.parse(
  await readFile(path.join(root, "ios/Harbor/MusicArtistAssets.json"), "utf8"),
);
const digest = createHash("sha256").update(asset.program.source).digest("hex");
assert.equal(digest, asset.program.sha256);

const A = "11111111-1111-4111-8111-111111111111";
const B = "44444444-4444-4444-8444-444444444444";
const musicBrainz = {
  id: A,
  name: "Owned Artist",
  "begin-area": { name: "Owned Town" },
  area: { name: "Owned Country" },
  "life-span": { begin: "1999-04", end: "2012" },
  aliases: [
    { name: "Owned Artist" },
    { name: "The Owned" },
    { name: "Owned Alias" },
    { name: "The Owned" },
  ],
  genres: [
    { name: "synth", count: 3 },
    { name: "ambient", count: 9 },
    { name: "drone", count: 1 },
  ],
  relations: [
    { type: "member of band", artist: { id: B, name: "Owned Member", disambiguation: "drums" } },
    { type: "collaboration", artist: { id: "not-a-uuid", name: "Rejected" } },
    { type: "official homepage", url: { resource: "https://owned.example/home" } },
    { type: "official homepage", url: { resource: "https://owned.example/home" } },
    { type: "merchandise", url: { resource: "https://shop.owned.example/" } },
    { type: "purchase for download", url: { resource: "https://www.qobuz.com/artist/1" } },
    { type: "purchase for download", url: { resource: "https://www.qobuz.com/artist/2" } },
    { type: "free streaming", url: { resource: "https://owned.bandcamp.com/" } },
    { type: "social network", url: { resource: "https://www.instagram.com/owned/" } },
    { type: "free streaming", url: { resource: "https://www.deezer.com/artist/8" } },
    {
      type: "streaming music",
      url: { resource: "https://open.spotify.com/artist/AAAAAAAAAAAAAAAAAAAAAA" },
    },
    {
      type: "youtube",
      url: { resource: "https://www.youtube.com/channel/UCaaaaaaaaaaaaaaaaaaaaaa" },
    },
    { type: "free streaming", url: { resource: "https://play.google.com/music/x" } },
    { type: "official homepage", ended: true, url: { resource: "https://old.example/" } },
    { type: "official homepage", url: { resource: "http://127.0.0.1/private" } },
    { type: "free streaming", url: { resource: "https://songkick.com/artists/1" } },
    { type: "wikidata", url: { resource: "https://www.wikidata.org/wiki/Q42" } },
  ],
};
const wikidata = {
  entities: {
    Q42: {
      claims: {
        P434: [{ mainsnak: { datavalue: { value: A } } }],
        P18: [{ mainsnak: { datavalue: { value: "Owned photo.jpg" } } }],
      },
      sitelinks: {
        eswiki: { url: "https://es.wikipedia.org/wiki/Owned_Artist", title: "Owned Artist" },
        enwiki: { url: "https://en.wikipedia.org/wiki/Owned_Artist", title: "Owned Artist" },
      },
      descriptions: { es: { value: "Artista de prueba" }, en: { value: "Test artist" } },
    },
  },
};
const summary = {
  type: "standard",
  extract: "Resumen original del artista de prueba.",
  originalimage: { source: "https://upload.wikimedia.org/owned/photo.jpg" },
};
const responses = {
  [`https://musicbrainz.org/ws/2/artist/${A}?inc=url-rels%2Bartist-rels%2Bgenres%2Baliases&fmt=json`]:
    musicBrainz,
  "https://www.wikidata.org/wiki/Special:EntityData/Q42.json": wikidata,
  "https://es.wikipedia.org/api/rest_v1/page/summary/Owned%20Artist": summary,
};

const requested = [];
const context = vm.createContext({
  URL,
  URLSearchParams,
  AbortController,
  TextEncoder,
  setTimeout,
  clearTimeout,
  Date,
  harbor: {
    async http(url) {
      requested.push(url);
      assert(Object.hasOwn(responses, url), `Unexpected request ${url}`);
      return { ok: true, status: 200, headers: {}, body: JSON.stringify(responses[url]) };
    },
  },
});
vm.runInContext(asset.program.source, context);
const call = (input) => context.plugin.content(input);

const parsed = await call({ operation: "parseProfile", data: musicBrainz, id: A });
assert.equal(await call({ operation: "parseProfile", data: musicBrainz, id: B }), null);
assert.equal(
  await call({ operation: "parseProfile", data: { ...musicBrainz, name: " " }, id: A }),
  null,
);
assert.equal(await call({ operation: "parseProfile", data: musicBrainz, id: "not-a-uuid" }), null);
const artist = {
  id: `musicbrainz:artist:${A}`,
  connectorId: "catalog",
  name: "Owned Artist",
  musicBrainzId: A,
};
const full = await call({ operation: "profile", artist, language: "es", requestId: "fixture" });
assert.equal(parsed.aliases.length, 2);
assert.deepEqual(parsed.genres, ["ambient", "synth", "drone"]);
assert.equal(parsed.members.length, 1);
assert(parsed.links.some((link) => link.kind === "store" && link.url.includes("qobuz")));
assert.equal(parsed.links.filter((link) => link.url.includes("qobuz")).length, 1);
assert(!parsed.links.some((link) => /127\.0\.0\.1|old\.example|play\.google/.test(link.url)));
assert.equal(full.biography, summary.extract);
assert.equal(full.biographyUrl, "https://es.wikipedia.org/wiki/Owned_Artist");
assert.equal(full.artwork, "https://upload.wikimedia.org/owned/photo.jpg");
assert.equal(full.wikidataId, "Q42");

const bytes =
  JSON.stringify(
    {
      schema: 1,
      reference: asset.reference,
      program_sha256: asset.program.sha256,
      artist_id: A,
      artist,
      language: "es",
      musicbrainz: musicBrainz,
      responses,
      expected_parse: parsed,
      expected_profile: full,
      requests_in_order: requested,
    },
    null,
    2,
  ) + "\n";
await writeFile(
  path.join(root, "ios/HarborTests/Fixtures/music-artist-profile-reference.json"),
  bytes,
);
console.log(
  `Original artist profile fixture: ${parsed.links.length} links, ${parsed.members.length} member, program ${asset.program.sha256}`,
);
