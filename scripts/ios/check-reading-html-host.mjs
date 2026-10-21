import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { load } from "cheerio";
import vm from "node:vm";

const asset = JSON.parse(await readFile("ios/Harbor/ReadingHTMLAssets.json", "utf8"));
const fixture = JSON.parse(
  await readFile("ios/HarborTests/Fixtures/reading-html-reference.json", "utf8"),
);
const host = await readFile("ios/Harbor/PluginRuntimeHost.js", "utf8");
class Element {
  constructor($, node) {
    this.$ = $;
    this.node = node;
  }
  querySelector(selector) {
    const node = this.$(this.node).find(selector).first()[0];
    return node ? new Element(this.$, node) : null;
  }
  querySelectorAll(selector) {
    return this.$(this.node)
      .find(selector)
      .toArray()
      .map((node) => new Element(this.$, node));
  }
  getAttribute(name) {
    return this.$(this.node).attr(name) ?? null;
  }
  get textContent() {
    return this.$(this.node).text();
  }
}
class Parser {
  parseFromString(html) {
    const $ = load(html);
    return new Element($, $.root()[0]);
  }
}
function create(config) {
  const messages = [],
    held = [];
  let hold = false;
  const context = vm.createContext({
    DOMParser: Parser,
    URL,
    Promise,
    TextEncoder,
    setTimeout,
    webkit: {
      messageHandlers: {
        harborPlugin: {
          postMessage(text) {
            const message = JSON.parse(text);
            messages.push(message);
            if (message.type !== "http") return;
            const respond = () => {
              const url = message.payload.url;
              const key = url.includes("/book/")
                ? "detail"
                : url.includes("/chapter/")
                  ? "chapter"
                  : "catalog";
              context.harborPluginHost.bridgeResult({
                id: message.id,
                ok: true,
                value: { ok: true, status: 200, body: fixture.documents[key] },
              });
            };
            if (hold && message.payload.url.includes("/popular")) held.push(respond);
            else queueMicrotask(respond);
          },
        },
      },
    },
  });
  vm.runInContext(host, context);
  const factory = vm.runInContext(asset.program.source, context);
  context.installHarborPluginHost("", () => {}, {}, "owned-html-host", factory);
  context.harborPluginHost.initialize({
    format: "trusted-html",
    source: JSON.stringify({ kind: "ebook", raw: JSON.stringify(config) }),
  });
  return {
    context,
    messages,
    held,
    hold: () => {
      hold = true;
    },
    api: context.harborPluginHost,
  };
}
async function wait(predicate) {
  for (let i = 0; i < 1000; i++) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  assert.fail("Owned HTML host did not reply");
}
const config = fixture.fixtures.find((row) => row.kind === "ebook").config;
const h = create(config);
await wait(() => h.messages.some((message) => message.type === "ready"));
assert(h.messages.every((message) => message.instance === "owned-html-host"));
h.api.call({ id: "detail", method: "detail", args: ["/book/one"], jsonResult: true });
await wait(() =>
  h.messages.some((message) => message.id === "detail" && message.type === "result"),
);
assert.equal(
  JSON.parse(h.messages.find((message) => message.id === "detail").value).title,
  "The Book",
);
h.hold();
h.api.call({ id: "cancelled", method: "popular", args: [0] });
await wait(() => h.held.length === 1);
h.api.cancel("cancelled");
assert(h.messages.some((message) => message.id === "cancelled" && message.type === "cancelled"));
h.api.call({ id: "other", method: "content", args: ["/chapter/one"] });
await wait(() => h.messages.some((message) => message.id === "other" && message.type === "result"));
h.held.shift()();
await new Promise((resolve) => setTimeout(resolve, 10));
assert(!h.messages.some((message) => message.id === "cancelled" && message.type === "result"));
h.api.call({ id: "disposed", method: "popular", args: [0] });
await wait(() => h.held.length === 1);
h.api.dispose();
h.held.shift()();
await new Promise((resolve) => setTimeout(resolve, 10));
assert(
  !h.messages.some(
    (message) => message.id === "disposed" && ["result", "error"].includes(message.type),
  ),
);
const invalid = create({});
await wait(() => invalid.messages.some((message) => message.type === "initError"));
invalid.api.dispose();
const marker = "'; globalThis.installedSourceExecuted=true; //";
const data = create({ ...config, name: marker });
await wait(() => data.messages.some((message) => message.type === "ready"));
assert.equal(data.messages.find((message) => message.type === "ready").meta.name, marker);
assert.equal(data.context.installedSourceExecuted, undefined);
data.api.dispose();
console.log(
  JSON.stringify({
    trustedHTMLHostCases: 6,
    passed: true,
    nativeExecution: false,
    existingWorkerCasesRepeated: false,
  }),
);
