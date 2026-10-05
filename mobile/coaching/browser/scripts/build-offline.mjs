import { readFile,writeFile,readdir,stat,realpath } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {createHash} from 'node:crypto';

const project=fileURLToPath(new URL('../../',import.meta.url));
const output=path.resolve(process.argv[2] ?? path.join(project,'build/web'));
const actual=await realpath(output),workspace=await realpath(project);
if(!actual.toLowerCase().startsWith(workspace.toLowerCase()+path.sep))throw Error('Offline output must be inside the Flutter project');
for(const file of ['index.html','main.dart.js','recognizer/bridge.js','canvaskit/canvaskit.wasm'])await stat(path.join(output,file));
// Flutter Web uses AssetManifest.bin.json (JSON/base64 transport), as defined by
// SDK services/asset_manifest.dart. The native-only raw .bin can be suppressed
// by browser/network binary filters; it is not a Web runtime dependency.
const excluded=new Set(['iqtadi-offline-manifest.json','iqtadi_service_worker.js','flutter_service_worker.js','.last_build_id','assets/AssetManifest.bin']);
async function files(folder,prefix='') {
  const result=[];
  for(const entry of await readdir(folder,{withFileTypes:true})){
    const relative=prefix+entry.name;
    if(entry.isSymbolicLink())throw Error('Symlink in static build');
    if(entry.isDirectory())result.push(...await files(path.join(folder,entry.name),relative+'/'));
    else if(entry.isFile()&&!excluded.has(relative)&&!relative.endsWith('.map')){
      const bytes=await readFile(path.join(folder,entry.name));
      result.push({path:relative,sha256:createHash('sha256').update(bytes).digest('hex'),size:bytes.byteLength});
    }
  }return result.sort((a,b)=>a.path.localeCompare(b.path));
}
const assets=await files(output),model=JSON.parse(await readFile(path.join(output,'recognizer/assets/manifest.json'),'utf8'));
const worker=await readFile(path.join(project,'web/iqtadi_service_worker.js'),'utf8');
const service_worker_sha256=createHash('sha256').update(worker).digest('hex');
const version=createHash('sha256').update(JSON.stringify({schema_version:'1.0.0',model_version:model.model_version,service_worker_sha256,files:assets})).digest('hex').slice(0,24);
const manifest={schema_version:'1.0.0',prediction_schema_version:model.schema_version,model_version:model.model_version,service_worker_sha256,version,files:assets};
await writeFile(path.join(output,'iqtadi-offline-manifest.json'),JSON.stringify(manifest,null,2));
await writeFile(path.join(output,'iqtadi_service_worker.js'),worker.replace('__IQTADI_OFFLINE_VERSION__',version));
console.log(JSON.stringify({offline_version:version,assets:assets.length,total_bytes:assets.reduce((n,f)=>n+f.size,0),output}));
