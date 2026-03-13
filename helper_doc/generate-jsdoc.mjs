import fs from "node:fs/promises";
import path from "node:path";
import jsdoc2md from "jsdoc-to-markdown";

const MDX_EXTENSION = ".mdx";
const OUTPUT_DIR = path.join(process.cwd(), "api_reference", "javascript");
const JS_FILES = [
  "scripts/CCIPLocalSimulatorFork.js",
  "scripts/data-streams/DataStreamsLocalSimulatorFork.js",
  "scripts/data-streams/MockReportGenerator.js",
  "scripts/data-streams/ReportVersions.js",
];

async function ensureDir(dirPath) {
  await fs.mkdir(dirPath, { recursive: true });
}

async function generateMarkdownDocs(files, outputDirectory) {
  await fs.rm(outputDirectory, { recursive: true, force: true });
  await ensureDir(outputDirectory);

  for (const file of files) {
    const absoluteFilePath = path.join(process.cwd(), file);
    const fileName = path.basename(file, path.extname(file));
    const outputPath = path.join(outputDirectory, `${fileName}${MDX_EXTENSION}`);
    const markdown = await jsdoc2md.render({ files: absoluteFilePath });
    const fixedMarkdown = markdown.replace(/&lt;\{/g, "&lt;\\{");
    await fs.writeFile(outputPath, fixedMarkdown, "utf8");
  }
}

generateMarkdownDocs(JS_FILES, OUTPUT_DIR)
  .then(() => console.log("Javascript API docs generated successfully."))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
