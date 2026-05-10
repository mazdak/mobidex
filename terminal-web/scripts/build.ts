import { cp, mkdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repo = resolve(root, "..");
const dist = resolve(root, "dist");
const iosTarget = resolve(repo, "Sources/Mobidex/TerminalWeb");
const androidTarget = resolve(repo, "android-app/src/main/assets/terminal");

async function copyDist(target: string) {
  await rm(target, { force: true, recursive: true });
  await mkdir(target, { recursive: true });
  await cp(dist, target, { recursive: true });
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

await copyDist(iosTarget);
await copyDist(androidTarget);
