import fs from "node:fs";
import path from "node:path";
import ts from "typescript";
const base = path.resolve(process.argv[2], "src/lib/i18n");
const out = path.resolve(process.argv[3]);
const cache = new Map();
const active = new Set();
function moduleData(file) {
  file = path.resolve(file);
  if (!file.startsWith(base + path.sep)) throw new Error("Locale dependency outside the reference");
  if (cache.has(file)) return cache.get(file);
  if (active.has(file)) throw new Error("Cyclic locale import");
  active.add(file);
  const node = ts.createSourceFile(
    file,
    fs.readFileSync(file, "utf8"),
    ts.ScriptTarget.Latest,
    true,
  );
  if (node.parseDiagnostics.length) throw new Error("Locale syntax error: " + file);
  const variables = new Map();
  const imports = new Map();
  let exported;
  for (const statement of node.statements) {
    if (ts.isImportDeclaration(statement) && statement.importClause?.name) {
      const relative = statement.moduleSpecifier.text;
      if (!relative.startsWith(".")) throw new Error("Nonlocal locale import");
      imports.set(
        statement.importClause.name.text,
        path.resolve(path.dirname(file), relative + ".ts"),
      );
    }
    if (ts.isVariableStatement(statement)) {
      for (const declaration of statement.declarationList.declarations) {
        if (ts.isIdentifier(declaration.name))
          variables.set(declaration.name.text, declaration.initializer);
      }
    }
    if (ts.isExportAssignment(statement)) exported = statement.expression;
  }
  const resolved = new Map();
  function evaluate(value) {
    if (ts.isStringLiteral(value) || ts.isNoSubstitutionTemplateLiteral(value)) return value.text;
    if (value.kind === ts.SyntaxKind.TrueKeyword) return true;
    if (value.kind === ts.SyntaxKind.FalseKeyword) return false;
    if (
      ts.isAsExpression(value) ||
      ts.isSatisfiesExpression(value) ||
      ts.isParenthesizedExpression(value)
    )
      return evaluate(value.expression);
    if (ts.isArrayLiteralExpression(value)) return value.elements.map(evaluate);
    if (ts.isElementAccessExpression(value) && ts.isStringLiteral(value.argumentExpression)) {
      const object = evaluate(value.expression);
      const key = value.argumentExpression.text;
      if (!Object.hasOwn(object, key)) throw new Error("Missing literal locale reference");
      return object[key];
    }
    if (ts.isObjectLiteralExpression(value)) {
      const object = Object.create(null);
      for (const item of value.properties) {
        if (ts.isSpreadAssignment(item)) Object.assign(object, evaluate(item.expression));
        else if (
          ts.isPropertyAssignment(item) &&
          (ts.isStringLiteral(item.name) || ts.isIdentifier(item.name))
        )
          object[item.name.text] = evaluate(item.initializer);
        else throw new Error("Nonliteral locale property: " + file);
      }
      return object;
    }
    if (ts.isIdentifier(value)) {
      const name = value.text;
      if (resolved.has(name)) return resolved.get(name);
      const result = imports.has(name)
        ? moduleData(imports.get(name)).defaultValue()
        : variables.has(name)
          ? evaluate(variables.get(name))
          : undefined;
      if (result === undefined) throw new Error("Unknown locale identifier: " + name);
      resolved.set(name, result);
      return result;
    }
    throw new Error(
      "Executable locale expression rejected: " +
        ts.SyntaxKind[value.kind] +
        " in " +
        file +
        ": " +
        value.getText(node).slice(0, 160),
    );
  }
  const result = {
    defaultValue: () => evaluate(exported),
    namedValue: (name) => evaluate(variables.get(name)),
  };
  cache.set(file, result);
  active.delete(file);
  return result;
}
const languages = moduleData(path.join(base, "languages.ts")).namedValue("LANGUAGES");
if (languages.length !== 16 || new Set(languages.map((x) => x.code)).size !== 16)
  throw new Error("Review the reference language inventory");
const catalogs = Object.fromEntries(
  languages.map((language) => {
    const table = moduleData(path.join(base, "locales", language.code + ".ts")).defaultValue();
    if (Object.values(table).some((value) => typeof value !== "string"))
      throw new Error("Nontext locale value");
    return [language.code, table];
  }),
);
fs.writeFileSync(out, JSON.stringify({ languages, catalogs }));
console.log(
  JSON.stringify({
    languages: languages.map((x) => x.code),
    counts: Object.fromEntries(
      Object.entries(catalogs).map(([code, values]) => [code, Object.keys(values).length]),
    ),
  }),
);
