import { RecognizerClient } from './client.mjs';
import { manifestAt } from './assets.mjs';
import { SCHEMA_VERSION } from './core.mjs';
import { buildLocalReport, LOCAL_LIMITS } from './session.mjs';
import { LocalSessionStore } from './storage.mjs';
import { thumbnailSize, canvasFor } from './image.mjs';

const base = new URL('./',import.meta.url).href;
const client = new RecognizerClient(base), storage = new LocalSessionStore();
let initialization, storageInitialization, modelVersion;
async function ensureStorage() {
  storageInitialization ??= (async () => {
    modelVersion ??= (await manifestAt(base)).model_version;
    return storage.initialize(modelVersion);
  })().catch(error => { storageInitialization = null; throw error; });
  return storageInitialization;
}
async function initialize() {
  initialization ??= (async () => {
    const info = await client.initialize(); modelVersion = info.model_version;
    let persistence;
    try { persistence = await ensureStorage(); }
    catch (error) { persistence = {storage_available:false,storage_warning:error.message}; }
    return {...info,...persistence,...LOCAL_LIMITS,schema_version:SCHEMA_VERSION,
      max_duration_ms:1200000,max_frames:2400,max_dimension:960,max_frame_bytes:200000,batch_frames:1,
      live_enabled:true,live_modes:['buffered','adaptive'],
      model_ready:true,inference_provider:'local',analysis_mode:'local',synthetic:false};
  })().catch(error => { initialization = null; throw error; });
  return initialization;
}
async function previewJpeg(value) {
  const canvas = canvasFor(value.preview), ctx = canvas.getContext('2d'), points = value.landmarks;
  ctx.strokeStyle = '#2be5a3'; ctx.fillStyle = '#ffbe3b'; ctx.lineWidth = 3;
  for (const [a,b] of [[11,12],[11,13],[13,15],[12,14],[14,16],[11,23],[12,24],[23,24],[23,25],[25,27],[24,26],[26,28],[27,29],[29,31],[28,30],[30,32]]) {
    if ((points[a]?.visibility ?? 0) >= .2 && (points[b]?.visibility ?? 0) >= .2) { ctx.beginPath();ctx.moveTo(points[a].x*384,points[a].y*512);ctx.lineTo(points[b].x*384,points[b].y*512);ctx.stroke(); }
  }
  for (const point of points) if ((point.visibility ?? 0) >= .2) { ctx.beginPath();ctx.arc(point.x*384,point.y*512,3,0,2*Math.PI);ctx.fill(); }
  const blob = canvas.convertToBlob ? await canvas.convertToBlob({type:'image/jpeg',quality:.85}) : await new Promise(resolve => canvas.toBlob(resolve,'image/jpeg',.85));
  if (!blob) throw Error('LOCAL_PREVIEW_ENCODE_FAILED'); return new Uint8Array(await blob.arrayBuffer());
}
async function analyze(jpeg) {
  await initialize();
  const bytes = jpeg instanceof Uint8Array ? jpeg : new Uint8Array(jpeg);
  if (!bytes.byteLength || bytes.byteLength > 50*1024*1024) throw Error('INVALID_IMAGE_SIZE');
  const value = await client.analyze(new Blob([bytes],{type:'image/jpeg'}));
  return {...value,preview_jpeg:await previewJpeg(value)};
}
// Calibration/legacy geometry uses actual source image coordinates. Inference
// always keeps the untouched 384x512 normalized landmarks and feature contract.
async function estimatePose(source) {
  await initialize();
  if (client.busy) return []; // Legacy frame scheduler drops busy frames, never queues.
  const width = source.videoWidth || source.naturalWidth || source.width;
  const height = source.videoHeight || source.naturalHeight || source.height;
  if (!width || !height) return [];
  const value = await client.analyze(source);
  const [w,h] = thumbnailSize(width,height), left=Math.floor((384-w)/2),top=Math.floor((512-h)/2);
  const degrees = value.result.recovery_method === 'rotate_minus_5' ? -5 : value.result.recovery_method === 'rotate_plus_5' ? 5 : 0;
  const angle = -degrees*Math.PI/180, a=Math.cos(angle),b=Math.sin(angle);
  return value.landmarks.map(point => { const x=point.x*384-192,y=point.y*512-256;
    return {...point,x:(a*x+b*y+192-left)/w,y:(-b*x+a*y+256-top)/h,z:point.z*384/w}; });
}
async function report(prayer,samples,options = {}) {
  modelVersion ??= options.model_version ?? samples[0]?.result?.model_version ?? (await manifestAt(base)).model_version;
  return buildLocalReport(prayer,samples,{model_version:modelVersion,...options});
}
async function exportSession(id) {
  await ensureStorage(); const text=await storage.exportSession(id);
  downloadJson(text,id);return text;
}
function downloadJson(text,id) {
  const url=URL.createObjectURL(new Blob([text],{type:'application/json'})),link=document.createElement('a');
  const safeId=String(id??'local-report').replace(/[^a-zA-Z0-9_-]/g,'_').slice(0,128);
  link.href=url;link.download='iqtadi-'+safeId+'.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
async function exportReport(payload) {
  const evidence=[];
  for(const item of payload.evidence??[]){
    if(item.jpeg_base64){evidence.push(item);continue;}
    const bytes=item.bytes instanceof Uint8Array?item.bytes:new Uint8Array(item.bytes);let binary='';
    for(let offset=0;offset<bytes.length;offset+=8192)binary+=String.fromCharCode(...bytes.subarray(offset,offset+8192));
    evidence.push({id:item.id,jpeg_base64:btoa(binary)});
  }
  const text=JSON.stringify({...payload,evidence},null,2);downloadJson(text,payload.id);return text;
}
window.iqtadiLocal = Object.freeze({ initialize,analyze,estimatePose,report,
  saveSession:async input=>{await ensureStorage();return storage.saveSession(input);},
  listSessions:async()=>{await ensureStorage();return storage.listSessions();},
  loadSession:async id=>{await ensureStorage();return storage.loadSession(id);},
  loadEvidence:async(id,evidenceId)=>{await ensureStorage();return storage.loadEvidence(id,evidenceId);},
  deleteSession:async id=>{await ensureStorage();return storage.deleteSession(id);},exportSession,exportReport,
  offlineStatus:()=>window.iqtadiOffline?.status?.() ?? {ready:false,state:'unavailable'},
  close:async()=>{await client.close();storage.close();initialization=storageInitialization=null;} });
window.dispatchEvent(new Event('iqtadi-local-ready'));
