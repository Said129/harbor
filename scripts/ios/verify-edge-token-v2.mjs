import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = (await readFile("ios/Harbor/EBookEdgeTokenV2.js", "utf8")).replaceAll("\r\n", "\n");
const context = vm.createContext({});
vm.runInContext(source, context, { timeout: 1000 });
const fixture = JSON.parse(
  await readFile("ios/HarborTests/Fixtures/edge-token-v2-reference.json", "utf8"),
);
assert.equal(
  fixture.sourceSHA256,
  "b29c37e2a0c11284adb2a1ffc04f0f231e1ba2d921494a912797218b05d64c4a",
);
assert.equal(fixture.cases.length, 129);
for (const item of fixture.cases)
  assert.equal(context.harborEdgeTokenV2(item.salt), item.expected, String(item.unix));
assert.throws(() => context.harborEdgeTokenV2("invalid"));
const hash = createHash("sha256").update(source).digest("hex");
assert((await readFile("ios/Harbor/Services/EBookNarration.swift", "utf8")).includes(hash));
assert(
  (await readFile("ios/Harbor/EBookNarrationNotices.txt", "utf8")).includes(
    "GNU LESSER GENERAL PUBLIC LICENSE",
  ),
);
console.log(
  "All 129 independent v2 tokens match; program SHA-256 and bundled LGPL notice are present.",
);
