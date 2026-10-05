import { build } from 'esbuild';
import { cp, mkdir, readFile, writeFile, realpath, lstat, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { preservePresence } from './mediapipe-presence.mjs';
import { createHash } from 'node:crypto';
const root = fileURLToPath(new URL('../', import.meta.url));
const out = path.resolve(root, '../web/recognizer');
const manifest = JSON.parse(await readFile(path.join(root, 'assets/manifest.json'), 'utf8'));
for (const [name, expected] of Object.entries(manifest.pipeline)) {
  if (createHash('sha256').update(await readFile(path.join(root, name))).digest('hex') !== expected) throw Error('Pipeline changed: re-run export_models.py before building. Changed file: ' + name);
}
const presencePlugin = { name: 'mediapipe-presence', setup(builder) {
  builder.onLoad({ filter: /vision_bundle\.mjs$/ }, async ({ path: sourcePath }) => ({ contents: preservePresence(await readFile(sourcePath, 'utf8')), loader: 'js' }));
} };
await mkdir(out, { recursive: true });
// This dedicated generated folder was created by this build, never used for source.
// Refuse symlinks/redirected parents before cleaning stale chunks and vendor binaries.
const actualParent = await realpath(path.dirname(out));
if (actualParent.toLowerCase() !== path.resolve(root, '../web').toLowerCase() || (await lstat(out)).isSymbolicLink()) throw Error('Unsafe generated output directory');
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
await build({ entryPoints: { app: path.join(root, 'src/app.mjs'), client: path.join(root, 'src/client.mjs'),bridge: path.join(root,'src/bridge.mjs') },
  outdir: out, bundle: true, splitting: true, format: 'esm', target: ['es2022'], sourcemap: true, conditions: ['onnxruntime-web-use-extern-wasm'], chunkNames: 'chunks/[name]-[hash]', minify: true, plugins: [presencePlugin] });
await build({ entryPoints: [path.join(root, 'src/worker.mjs')], outfile: path.join(out, 'worker.js'), bundle: true,
  format: 'iife', target: ['es2022'], sourcemap: true, conditions: ['onnxruntime-web-use-extern-wasm'], minify: true, plugins: [presencePlugin] });
await cp(path.join(root, 'src/index.html'), path.join(out, 'index.html'));
await cp(path.join(root, 'src/style.css'), path.join(out, 'style.css'));
await mkdir(path.join(out, 'fonts'), { recursive: true });
for (const name of ['NotoSansArabic.ttf', 'OFL.txt']) await cp(path.join(root, '../assets/fonts', name), path.join(out, 'fonts', name));
await cp(path.join(root, 'assets'), path.join(out, 'assets'), { recursive: true });
await mkdir(path.join(out, 'vendor/ort'), { recursive: true });
for (const name of ['ort-wasm-simd-threaded.wasm', 'ort-wasm-simd-threaded.mjs']) await cp(path.join(root, 'node_modules/onnxruntime-web/dist', name), path.join(out, 'vendor/ort', name));
await cp(path.join(root, 'node_modules/@mediapipe/tasks-vision/wasm'), path.join(out, 'vendor/vision'), { recursive: true });
await writeFile(path.join(out, 'build.json'), JSON.stringify({ schema_version: manifest.schema_version, model_version: manifest.model_version, built_at: new Date().toISOString() }, null, 2));
await cp(path.join(root, 'THIRD_PARTY_NOTICES.md'), path.join(out, 'THIRD_PARTY_NOTICES.md'));
console.log('Static recognizer built: ' + out);
