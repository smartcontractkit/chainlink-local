import fs from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = process.cwd();
const FORGE_DOC_TMP_DIR = path.join(ROOT, "cache_forge", "forge-docs-tmp");
const SOURCE_DOC_DIR = path.join(FORGE_DOC_TMP_DIR, "src", "src");
const API_REFERENCE_DIR = path.join(ROOT, "api_reference");
const OUTPUT_DIR = path.join(API_REFERENCE_DIR, "solidity");
const OUTPUT_TMP_DIR = path.join(API_REFERENCE_DIR, "solidity.tmp");

const EXCLUDED_PATH_SEGMENTS = new Set(["test", "vendor", "lib", "script", "scripts"]);
const DEF_DOC_RE = /^(contract|interface|library|abstract)\.(.+)\.md$/;

function runForgeDoc() {
  const result = spawnSync("forge", ["doc", "-o", FORGE_DOC_TMP_DIR], {
    cwd: ROOT,
    stdio: "inherit",
  });

  if (result.status !== 0) {
    throw new Error("forge doc failed");
  }
}

async function pathExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = await Promise.all(
    entries.map((entry) => {
      const entryPath = path.join(dir, entry.name);
      return entry.isDirectory() ? walk(entryPath) : [entryPath];
    })
  );
  return files.flat();
}

function shouldExclude(relativePath) {
  return relativePath.split(path.sep).some((segment) => EXCLUDED_PATH_SEGMENTS.has(segment));
}

function normalizeForMdx(content) {
  let normalized = content.replace(/^\[Git Source\]\([^)]+\)\n\n?/m, "");

  const headingMatch = normalized.match(/^#\s+(.+)\n/);
  if (headingMatch) {
    normalized = normalized.replace(/^#\s+(.+)\n/, "# Solidity API\n\n## $1\n");
  }

  return normalized;
}

async function generateMdxFiles() {
  if (!(await pathExists(SOURCE_DOC_DIR))) {
    throw new Error(`Forge doc output directory not found: ${SOURCE_DOC_DIR}`);
  }

  await fs.rm(OUTPUT_TMP_DIR, { recursive: true, force: true });
  await fs.mkdir(OUTPUT_TMP_DIR, { recursive: true });

  const files = await walk(SOURCE_DOC_DIR);
  let generated = 0;

  for (const filePath of files) {
    if (!filePath.endsWith(".md")) continue;

    const relativePath = path.relative(SOURCE_DOC_DIR, filePath);
    if (shouldExclude(relativePath)) continue;

    const baseName = path.basename(filePath);
    const match = baseName.match(DEF_DOC_RE);
    if (!match) continue;

    const symbolName = match[2];
    const relDir = path.dirname(relativePath);
    const withoutSourceFileDir = relDir.split(path.sep).slice(0, -1).join(path.sep);

    const targetDir = path.join(OUTPUT_TMP_DIR, withoutSourceFileDir);
    const targetFilePath = path.join(targetDir, `${symbolName}.mdx`);

    const content = await fs.readFile(filePath, "utf8");
    const mdxContent = normalizeForMdx(content);

    await fs.mkdir(targetDir, { recursive: true });
    await fs.writeFile(targetFilePath, mdxContent, "utf8");
    generated += 1;
  }

  if (generated === 0) {
    throw new Error("No Solidity docs were generated from forge doc output.");
  }

  await fs.rm(OUTPUT_DIR, { recursive: true, force: true });
  await fs.rename(OUTPUT_TMP_DIR, OUTPUT_DIR);

  console.log(`Generated ${generated} Solidity API files in ${OUTPUT_DIR}`);
}

async function main() {
  await fs.rm(FORGE_DOC_TMP_DIR, { recursive: true, force: true });
  runForgeDoc();
  await generateMdxFiles();
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
