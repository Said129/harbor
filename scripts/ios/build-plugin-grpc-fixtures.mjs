import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import ts from "typescript";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const args = process.argv.slice(2);
const index = args.indexOf("--reference");
assert(index >= 0 && args[index + 1], "Provide the pinned Desktop reference directory");
const name = "src/lib/manga/plugins/host-http.ts";
const source = (await readFile(path.join(path.resolve(args[index + 1]), name), "utf8")).replaceAll(
  "\r\n",
  "\n",
);
const digest = "9f88ca743ef87f50d820fb4ca2573d1837d5418279f1284839bf34410245f589";
assert.equal(createHash("sha256").update(source).digest("hex"), digest);
const compiled = ts.transpileModule(source, {
  fileName: name,
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  reportDiagnostics: true,
});
assert.equal(compiled.diagnostics?.length ?? 0, 0);
let response = { status: 200, headers: {}, bytes: new Uint8Array() };
let captured;
const exported = {};
vm.runInNewContext(
  compiled.outputText,
  {
    exports: exported,
    URL,
    Headers,
    TextDecoder,
    AbortSignal,
    atob,
    btoa,
    require(id) {
      if (id === "@/lib/safe-fetch")
        return {
          safeFetchBytes: async (url, init, timeout) => {
            assert.equal(url, "https://example.invalid/owned-grpc");
            captured = { frame: Buffer.from(init.body).toString("base64"), timeout };
            const actual = response;
            return {
              status: actual.status,
              ok: actual.status >= 200 && actual.status < 300,
              headers: new Headers(actual.headers),
              arrayBuffer: async () =>
                actual.bytes.buffer.slice(
                  actual.bytes.byteOffset,
                  actual.bytes.byteOffset + actual.bytes.byteLength,
                ),
            };
          },
        };
      // These fixtures exercise framing/decoding only, without real network or privacy/header-policy claims.
      if (id === "@/lib/privacy/blocklist") return { isBlockedUrl: () => false };
      if (id === "@/lib/subtitles/provider-url")
        return { SUBTITLE_PUBLIC_NETWORK_HEADER: "unused-in-grpc-framing" };
      if (id === "@/lib/same-site-host")
        return {
          sameSiteHost() {
            throw new Error("Header policy is outside these fixtures");
          },
        };
      throw new Error("Unexpected reference import " + id);
    },
  },
  { timeout: 1000 },
);

async function run(request, opts = {}) {
  captured = undefined;
  try {
    const value = await exported.runPluginGrpc("https://example.invalid/owned-grpc", request, opts);
    return { expected: JSON.parse(JSON.stringify(value)), captured };
  } catch (error) {
    return { error: error.message };
  }
}
const requests = [];
for (const input of [
  "",
  "AA==",
  "AQID",
  "AQI",
  " AB ",
  "\ufeffAQID\n",
  "A",
  "AA=",
  "AA===",
  "!!!!",
  "éééé",
  "AA-_",
  "A=AA",
  "AQID\u0085",
]) {
  const result = await run(input);
  requests.push({
    input,
    ...(result.error ? { error: result.error } : { expected: result.captured }),
  });
}
const timeouts = [];
for (const value of [null, 0, -1, 25, 1_000, 20_000, 60_000]) {
  const opts = value === null ? {} : { timeoutMs: value };
  const result = await run("", opts);
  assert(!result.error);
  timeouts.push({ value, expected: result.captured.timeout });
}
function frame(flags, bytes) {
  const payload = Buffer.from(bytes),
    header = Buffer.alloc(5);
  header[0] = flags;
  header.writeUInt32BE(payload.length, 1);
  return Buffer.concat([header, payload]);
}
const message = frame(0, [1, 2, 3]);
const responses = [];
const cases = [
  { bytes: message },
  { bytes: frame(0, []) },
  { bytes: Buffer.alloc(0) },
  {
    bytes: Buffer.concat([
      message,
      frame(0, [4, 5]),
      frame(0x80, "grpc-status: 0\r\ngrpc-message: caf%C3%A9%20%F0%9F%93%9A\r\n"),
    ]),
  },
  { bytes: message, headers: { "grpc-status": "7", "grpc-message": "Permission%20denied" } },
  {
    bytes: Buffer.concat([message, frame(0x80, "grpc-status: 0\ngrpc-message: invalid%ZZ\n")]),
    headers: { "grpc-status": "7" },
  },
  { bytes: message, headers: { "grpc-status": "0x0" } },
  { bytes: message, headers: { "grpc-status": "bogus" } },
  { bytes: message, headers: { "grpc-status": "Infinity" } },
  { bytes: message, headers: { "grpc-status": "" } },
  { bytes: message, status: 503 },
  { bytes: Buffer.from([0]) },
  { bytes: Buffer.from([0, 0, 0, 0, 4, 1, 2]) },
  { bytes: frame(1, [1]) },
  { bytes: frame(2, [1]) },
  { bytes: frame(0x81, "grpc-status: 0") },
];
for (const item of cases) {
  response = { status: item.status ?? 200, headers: item.headers ?? {}, bytes: item.bytes };
  const actual = await run("");
  responses.push({
    status: response.status,
    headers: response.headers,
    bytes: response.bytes.toString("base64"),
    ...(actual.error ? { error: actual.error } : { expected: actual.expected }),
  });
}
const fixture = {
  schema: 1,
  reference: "0834340cec5531650bfe78cd628628702e636987",
  inputs: { [name]: digest },
  networkExecuted: false,
  headerPolicyValidated: false,
  requests,
  timeouts,
  responses,
};
const target = path.join(root, "ios/HarborTests/Fixtures/plugin-grpc-reference.json");
if (args.includes("--check")) assert.deepEqual(JSON.parse(await readFile(target, "utf8")), fixture);
else await writeFile(target, JSON.stringify(fixture, null, 2) + "\n");
process.stdout.write(
  JSON.stringify({
    requests: requests.length,
    timeouts: timeouts.length,
    responses: responses.length,
    desktopFramingExecuted: true,
    nativeExecuted: false,
    networkExecuted: false,
  }) + "\n",
);
