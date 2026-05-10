import { cp, mkdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repo = resolve(root, "..");
const dist = resolve(root, "dist");
const iosTarget = resolve(repo, "Sources/Mobidex/TerminalWeb");
const androidTarget = resolve(repo, "android-app/src/main/assets/terminal");

async function copyDist(target: string, options: { includeIosEntry?: boolean } = {}) {
  await rm(target, { force: true, recursive: true });
  await mkdir(target, { recursive: true });
  await cp(dist, target, { recursive: true });
  if (!options.includeIosEntry) {
    await rm(resolve(target, "index-ios.html"), { force: true });
  }
}

await rm(dist, { force: true, recursive: true });
await mkdir(dist, { recursive: true });

const result = await Bun.build({
  entrypoints: [resolve(root, "src/mobidex-terminal.ts")],
  outdir: dist,
  target: "browser",
  format: "esm",
  minify: true,
  sourcemap: "none",
});

if (!result.success) {
  for (const log of result.logs) {
    console.error(log);
  }
  process.exit(1);
}

await cp(resolve(root, "src/index.html"), resolve(dist, "index.html"));
await cp(
  resolve(root, "node_modules/@wterm/ghostty/wasm/ghostty-vt.wasm"),
  resolve(dist, "ghostty-vt.wasm"),
);

const [html, css, js] = await Promise.all([
  Bun.file(resolve(dist, "index.html")).text(),
  Bun.file(resolve(dist, "mobidex-terminal.css")).text(),
  Bun.file(resolve(dist, "mobidex-terminal.js")).text(),
]);
const inlineHtml = html
  .replace(
    '    <link rel="stylesheet" href="./mobidex-terminal.css" />',
    `    <style>${css}</style>`,
  )
  .replace(
    '    <script type="module" src="./mobidex-terminal.js"></script>',
    `    <script type="module">${js}</script>`,
  );
await Bun.write(resolve(dist, "index-ios.html"), inlineHtml);

await copyDist(iosTarget, { includeIosEntry: true });
await copyDist(androidTarget);
