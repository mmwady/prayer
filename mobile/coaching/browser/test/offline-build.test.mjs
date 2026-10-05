import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm,realpath} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const run=promisify(execFile),project=fileURLToPath(new URL('../../',import.meta.url));
test('offline production cache uses the Web JSON manifest and invalidates when app or model version changes',async()=>{
 const cacheRoot=path.join(project,'browser/.cache');await mkdir(cacheRoot,{recursive:true});
 const output=await mkdtemp(path.join(cacheRoot,'offline-build-test-'));
 try{
  const files={'index.html':'local app shell','main.dart.js':'version one','recognizer/bridge.js':'local bridge',
   'canvaskit/canvaskit.wasm':'local wasm','assets/AssetManifest.bin':'native raw binary',
   'assets/AssetManifest.bin.json':'"bmF0aXZlIHJhdyBiaW5hcnk="',
   'recognizer/assets/manifest.json':JSON.stringify({schema_version:'2.0.0',model_version:'models-v1'})};
  for(const [name,body] of Object.entries(files)){const file=path.join(output,name);await mkdir(path.dirname(file),{recursive:true});await writeFile(file,body);}
  const build=async()=>{await run(process.execPath,[path.join(project,'browser/scripts/build-offline.mjs'),output]);return JSON.parse(await readFile(path.join(output,'iqtadi-offline-manifest.json'),'utf8'));};
  const original=await build();assert.ok(original.files.some(f=>f.path==='assets/AssetManifest.bin.json'));
  assert.ok(!original.files.some(f=>f.path==='assets/AssetManifest.bin'));assert.equal((await build()).version,original.version);
  await writeFile(path.join(output,'main.dart.js'),'version two');const updated=await build();assert.notEqual(updated.version,original.version);
  await writeFile(path.join(output,'recognizer/assets/manifest.json'),JSON.stringify({schema_version:'2.0.0',model_version:'models-v2'}));
  const models=await build();assert.notEqual(models.version,updated.version);assert.equal(models.model_version,'models-v2');
  assert.ok((await readFile(path.join(output,'iqtadi_service_worker.js'),'utf8')).includes("const APP_VERSION='"+models.version+"'"));
 }finally{
  const resolved=await realpath(output),parent=await realpath(cacheRoot);
  if(!resolved.toLowerCase().startsWith(parent.toLowerCase()+path.sep))throw Error('Unsafe temporary build cleanup');
  await rm(resolved,{recursive:true,force:true});
 }
});
