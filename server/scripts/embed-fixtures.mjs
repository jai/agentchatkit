// Writes src/fixtures.generated.ts from ../protocol/fixtures/*.json, so the conformance suite carries the fixtures
// into any runtime (a Worker has no file system). `npm run fixtures` after protocol/generate.py; a test checks it.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const source = join(root, "..", "protocol", "fixtures");

export function embedded() {
  const fixtures = {};
  for (const name of readdirSync(source)
    .filter((file) => file.endsWith(".json"))
    .sort()) {
    fixtures[name.replace(/\.json$/, "")] = JSON.parse(readFileSync(join(source, name), "utf8"));
  }
  return (
    "// Written by scripts/embed-fixtures.mjs from protocol/fixtures. Do not edit: run `npm run fixtures`.\n" +
    `export const fixtures: Record<string, unknown> = ${JSON.stringify(fixtures, null, 2)};\n`
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  writeFileSync(join(root, "src", "fixtures.generated.ts"), embedded());
}
