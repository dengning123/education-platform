import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceRoot = resolve(packageRoot, "src");

async function sourceFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) files.push(...await sourceFiles(path));
    else if (entry.isFile() && entry.name.endsWith(".ts")) files.push(path);
  }
  return files;
}

const hash = createHash("sha256");
for (const path of (await sourceFiles(sourceRoot)).sort()) {
  hash.update(relative(packageRoot, path).replaceAll("\\", "/"));
  hash.update("\0");
  hash.update(await readFile(path));
  hash.update("\0");
}
process.stdout.write(`${hash.digest("hex")}\n`);
