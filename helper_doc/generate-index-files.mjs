import fs from "node:fs/promises";
import path from "node:path";

const MDX_EXTENSION = ".mdx";
const ROOT_DIR = path.join(process.cwd(), "api_reference");

async function generateIndexFile(dir, header) {
  const dirents = await fs.readdir(dir, { withFileTypes: true });
  const mdxFiles = dirents
    .filter((entry) => entry.isFile() && entry.name.endsWith(MDX_EXTENSION) && entry.name !== `index${MDX_EXTENSION}`)
    .map((entry) => entry.name);
  const subDirs = dirents.filter((entry) => entry.isDirectory()).map((entry) => entry.name);

  let content = `# ${header}\n\n`;
  for (const entry of [...mdxFiles, ...subDirs]) {
    const isMdx = entry.endsWith(MDX_EXTENSION);
    const linkName = isMdx ? path.basename(entry, MDX_EXTENSION) : entry;
    const linkPath = isMdx ? entry : `${entry}/index${MDX_EXTENSION}`;
    content += `- [${linkName}](${linkPath})\n`;
  }

  await fs.writeFile(path.join(dir, `index${MDX_EXTENSION}`), content, "utf8");
}

async function traverseDirectory(dir, header) {
  await generateIndexFile(dir, header);

  const dirents = await fs.readdir(dir, { withFileTypes: true });
  const subDirs = dirents.filter((entry) => entry.isDirectory()).map((entry) => entry.name);

  for (const subDir of subDirs) {
    const subHeader = `${subDir.charAt(0).toUpperCase() + subDir.slice(1)} API Reference`;
    await traverseDirectory(path.join(dir, subDir), subHeader);
  }
}

traverseDirectory(ROOT_DIR, "API Reference")
  .then(() => console.log("Index files generated successfully."))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
