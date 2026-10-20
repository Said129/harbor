import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const asset = JSON.parse(
  await readFile(new URL("../../ios/Harbor/PluginRuntimeAssets.json", import.meta.url), "utf8"),
);
const composer = vm.runInNewContext(asset.programs.composer.source, {}, { timeout: 1000 });

function worker(
  source,
  bridge = () => {
    throw new Error("Unexpected owned fixture bridge");
  },
) {
  const messages = [];
  const waiting = [];
  const self = {
    close() {},
    postMessage(value) {
      const message = structuredClone(value);
      if (message.type === "http" || message.type === "grpc") {
        Promise.resolve()
          .then(() => bridge(message))
          .then((response) =>
            self.onmessage({
              data: { type: "bridgeResult", id: message.id, ok: true, value: response },
            }),
          );
      } else {
        messages.push(message);
        for (const waiter of waiting.slice()) {
          if (
            waiter.type === message.type &&
            (waiter.id === undefined || waiter.id === message.id)
          ) {
            waiting.splice(waiting.indexOf(waiter), 1);
            messages.splice(messages.indexOf(message), 1);
            clearTimeout(waiter.timer);
            waiter.resolve(message);
          }
        }
      }
    },
  };
  const context = vm.createContext({
    self,
    btoa,
    atob,
    URL,
    URLSearchParams,
    TextEncoder,
    TextDecoder,
  });
  vm.runInContext(asset.programs.sandbox.source, context, { timeout: 1000 });
  self.onmessage({ data: { type: "init", source, config: {} } });
  function next(type, id) {
    const index = messages.findIndex(
      (message) => message.type === type && (id === undefined || message.id === id),
    );
    if (index >= 0) return Promise.resolve(messages.splice(index, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = {
        type,
        id,
        resolve,
        timer: setTimeout(
          () =>
            reject(
              new Error(`Missing actual worker message ${type}/${id}: ${JSON.stringify(messages)}`),
            ),
          1000,
        ),
      };
      waiting.push(waiter);
    });
  }
  return { next, send: (message) => self.onmessage({ data: message }), messages };
}

test("pinned Harbor worker returns declared methods and preserves actual request arguments", async () => {
  const program = composer.harbor(
    `var plugin = { id: "owned.raw", name: "Owned", search: function (query, page) { return { query: query, page: page, directFetch: typeof fetch }; }, settings: function () { return [{ key: "quality", type: "select", label: "Quality", options: ["FHD"] }]; } };`,
  );
  const host = worker(program);
  const ready = await host.next("ready");
  assert.equal(ready.meta.id, "owned.raw");
  assert.deepEqual(ready.meta.methods, ["search", "settings"]);
  host.send({ type: "call", id: "owned-search", method: "search", args: ["café", 3] });
  assert.deepEqual((await host.next("result", "owned-search")).value, {
    query: "café",
    page: 3,
    directFetch: "undefined",
  });
  host.send({ type: "call", id: "missing", method: "chapters", args: [] });
  assert.match((await host.next("error", "missing")).error, /no method: chapters/);
});

test("provider scripts retain CommonJS, DOM, crypto and independent configured settings", async () => {
  const code = `const crypto = require("crypto-js"); const cheerio = require("cheerio"); module.exports.getStreams = function (id, kind, season, episode) { return [{ url: "https://example.invalid/" + id + "/" + kind + "/" + season + "/" + episode, name: crypto.MD5("abc").toString(), title: cheerio.load("<b>owned</b>")("b").text(), headers: { "x-owned": SCRAPER_SETTINGS.token, "x-buffer": Buffer.from("fixture").toString("base64") } }]; };`;
  for (const token of ["owned-a", "owned-b"]) {
    const host = worker(
      composer.provider(code, {
        id: "owned.provider",
        name: "Owned Provider",
        settings: { token },
      }),
    );
    assert.equal((await host.next("ready")).meta.id, "owned.provider");
    host.send({
      type: "call",
      id: token,
      method: "streams",
      args: [{ tmdb: { id: 42 }, type: "series", season: 2, episode: 7 }],
    });
    const result = (await host.next("result", token)).value[0];
    assert.equal(result.url, "https://example.invalid/42/tv/2/7");
    assert.equal(result.name, "900150983cd24fb0d6963f7d28e17f72");
    assert.equal(result.title, "owned");
    assert.deepEqual(result.headers, { "x-owned": token, "x-buffer": "Zml4dHVyZQ==" });
  }
});

test("HTTP JSON and gRPC bytes cross the original bridge contract without network access", async () => {
  const observed = [];
  const host = worker(
    `var plugin = { id: "owned.bridge", name: "Bridge", content: async function () { const json = await harbor.http("https://example.invalid/data", { responseType: "json", headers: { "x-owned": "fixture" } }); const binary = await harbor.grpc("https://example.invalid/grpc", new Uint8Array([1,2,3]), { mode: "grpc-web" }); return { json: json, body: Array.from(binary.body), message: Array.from(binary.messages[0]) }; } };`,
    (message) => {
      observed.push(message);
      return message.type === "http"
        ? { status: 200, body: '{"owned":true}', headers: {}, ok: true }
        : { status: 200, body: "BAUG", messages: ["BwgJ"], headers: {}, ok: true };
    },
  );
  await host.next("ready");
  host.send({ type: "call", id: "bridge", method: "content", args: [] });
  assert.deepEqual((await host.next("result", "bridge")).value, {
    json: { owned: true },
    body: [4, 5, 6],
    message: [7, 8, 9],
  });
  assert.equal(observed[0].payload.opts.responseType, "json");
  assert.equal(observed[0].payload.opts.headers["x-owned"], "fixture");
  assert.equal(observed[1].payload.requestBase64, "AQID");
  assert.equal(observed[1].payload.opts.mode, "grpc-web");
});

test("a cancelled worker operation acknowledges cancellation and cannot publish its late result", async () => {
  let release;
  const held = new Promise((resolve) => {
    release = resolve;
  });
  const host = worker(
    `var plugin = { id: "owned.cancel", name: "Cancel", search: async function () { return await harbor.http("https://example.invalid/held", { responseType: "json" }); } };`,
    () => held,
  );
  await host.next("ready");
  host.send({ type: "call", id: "cancelled", method: "search", args: [] });
  host.send({ type: "cancel", id: "cancelled" });
  assert.equal((await host.next("cancelled", "cancelled")).id, "cancelled");
  release({ status: 200, body: '{"late":true}', headers: {}, ok: true });
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(
    host.messages.some((message) => message.type === "result" && message.id === "cancelled"),
    false,
  );
});
