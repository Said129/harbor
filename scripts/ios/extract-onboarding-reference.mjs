import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import ts from "typescript";
import { Resvg } from "@resvg/resvg-js";

const reference = path.resolve(process.argv[2]);
const destination = path.resolve(process.argv[3]);
if (JSON.parse(fs.readFileSync(path.join(reference, "package.json"), "utf8")).version !== "0.9.132")
  throw new Error("Use the pinned Desktop 0.9.132 reference");
const sources = {};
function declarations(relative) {
  const bytes = fs.readFileSync(path.join(reference, relative));
  sources[relative] = crypto.createHash("sha256").update(bytes).digest("hex");
  const tree = ts.createSourceFile(relative, bytes.toString("utf8"), ts.ScriptTarget.Latest, true);
  if (tree.parseDiagnostics.length) throw new Error("Invalid reference syntax");
  const variables = new Map();
  for (const statement of tree.statements) {
    if (!ts.isVariableStatement(statement)) continue;
    for (const declaration of statement.declarationList.declarations) {
      if (ts.isIdentifier(declaration.name))
        variables.set(declaration.name.text, declaration.initializer);
    }
  }
  function literal(node) {
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text;
    if (ts.isNumericLiteral(node)) return Number(node.text);
    if (node.kind === ts.SyntaxKind.TrueKeyword) return true;
    if (node.kind === ts.SyntaxKind.FalseKeyword) return false;
    if (ts.isIdentifier(node) && variables.has(node.text)) return literal(variables.get(node.text));
    if (
      ts.isAsExpression(node) ||
      ts.isSatisfiesExpression(node) ||
      ts.isParenthesizedExpression(node)
    )
      return literal(node.expression);
    if (ts.isArrayLiteralExpression(node)) return node.elements.map(literal);
    if (ts.isObjectLiteralExpression(node)) {
      const result = {};
      for (const property of node.properties) {
        if (
          !ts.isPropertyAssignment(property) ||
          !(ts.isIdentifier(property.name) || ts.isStringLiteral(property.name))
        )
          throw new Error("Nonliteral reference property");
        result[property.name.text] = literal(property.initializer);
      }
      return result;
    }
    throw new Error("Executable reference expression rejected");
  }
  return { variables, literal };
}
const streaming = declarations("src/lib/providers/streaming.ts");
const logoComponent = fs.readFileSync(path.join(reference, "src/components/service-logo.tsx"));
sources["src/components/service-logo.tsx"] = crypto
  .createHash("sha256")
  .update(logoComponent)
  .digest("hex");
if (
  !logoComponent
    .toString("utf8")
    .includes('filter: "var(--service-logo-filter, brightness(0) invert(1))"')
)
  throw new Error("Review the reference logo rendering policy");
const settings = declarations("src/lib/settings/defaults.ts");
const defaultNode = settings.variables.get("DEFAULT");
if (!ts.isObjectLiteralExpression(defaultNode)) throw new Error("Review settings defaults");
const streamingNode = defaultNode.properties.find(
  (property) => property.name?.text === "streaming",
);
const defaults = settings.literal(streamingNode.initializer);
const services = streaming.literal(streaming.variables.get("SERVICES"));
if (Object.keys(services).length !== 27 || Object.keys(defaults).length !== 27)
  throw new Error("Review changed service inventory");
const catalog = [];
const assetSources = [];
for (const [key, service] of Object.entries(services)) {
  if (typeof defaults[key] !== "boolean") throw new Error("Missing service default");
  const relative = "public" + service.logo;
  const bytes = fs.readFileSync(path.join(reference, relative));
  const asset = "streaming-" + key;
  const folder = path.join(destination, "Assets.xcassets", asset + ".imageset");
  fs.mkdirSync(folder, { recursive: true });
  const png = service.logo.endsWith(".svg")
    ? new Resvg(bytes, { fitTo: { mode: "width", value: 360 } }).render().asPng()
    : bytes;
  fs.writeFileSync(path.join(folder, "logo.png"), png);
  fs.writeFileSync(
    path.join(folder, "Contents.json"),
    JSON.stringify(
      {
        images: [{ filename: "logo.png", idiom: "universal" }],
        info: { author: "xcode", version: 1 },
      },
      null,
      2,
    ) + "\n",
  );
  catalog.push({
    key,
    name: service.name,
    providerIds: service.providerIds ?? [service.id],
    enabledByDefault: defaults[key],
    asset,
    tint: service.tint,
    logoHeight: service.logoHeight ? Math.round(22 * (service.logoHeight / 32)) : 22,
  });
  assetSources.push({
    file: relative,
    sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
    asset,
  });
}
fs.writeFileSync(
  path.join(destination, "DesktopStreamingServices.json"),
  JSON.stringify(catalog, null, 2) + "\n",
);
fs.writeFileSync(
  path.join(destination, "DesktopStreamingSources.json"),
  JSON.stringify(
    { reference: "0834340cec5531650bfe78cd628628702e636987", sources, assets: assetSources },
    null,
    2,
  ) + "\n",
);
console.log(
  "Extracted 27 service definitions, defaults and logos without executing reference code.",
);
