// build-offline.mjs replaces this version in the completed static Flutter build.
const APP_VERSION='__IQTADI_OFFLINE_VERSION__';
const CACHE_NAME='iqtadi-app-'+APP_VERSION;
const appBase=()=>new URL('./',self.registration.scope);
let installStatus={ready:false,state:'preparing',version:APP_VERSION,completed:0,total:0};
async function notify(status,target) {
  installStatus={...installStatus,...status};
  const message={source:'iqtadi-offline',status:installStatus};
  if(target)target.postMessage(message);
  else for(const client of await self.clients.matchAll({includeUncontrolled:true}))client.postMessage(message);
}
self.addEventListener('install',event=>event.waitUntil((async()=>{
  if(APP_VERSION.startsWith('__'))throw Error('Run build-offline.mjs after flutter build web');
  const cache=await caches.open(CACHE_NAME);
  try {
    const manifestUrl=new URL('iqtadi-offline-manifest.json',appBase());
    const response=await fetch(manifestUrl,{cache:'no-store'});
    if(!response.ok)throw Error('Offline manifest unavailable');
    const manifest=await response.clone().json();
    if(manifest.version!==APP_VERSION || manifest.schema_version!=='1.0.0')throw Error('Offline build version mismatch');
    await notify({total:manifest.files.length,total_bytes:manifest.files.reduce((n,f)=>n+f.size,0)});
    let next=0,completed=0,bytes=0;
    async function download() {
      while(next<manifest.files.length) {
        const file=manifest.files[next++],url=new URL(file.path,appBase());
        if(url.origin!==self.location.origin || !url.pathname.startsWith(appBase().pathname))throw Error('Invalid offline asset URL');
        const asset=await fetch(url,{cache:'reload'});if(!asset.ok)throw Error('Offline asset unavailable: '+file.path);
        const buffer=await asset.clone().arrayBuffer();
        const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',buffer)),v=>v.toString(16).padStart(2,'0')).join('');
        if(hash!==file.sha256)throw Error('Offline asset version mismatch: '+file.path+'; expected '+file.sha256+'; received '+hash+'; '+buffer.byteLength+' bytes; '+asset.headers.get('Content-Type'));
        await cache.put(url,asset);completed++;bytes+=buffer.byteLength;
        await notify({completed,downloaded_bytes:bytes});
      }
    }
    await Promise.all([download(),download(),download()]);
    await cache.put(manifestUrl,response);
    await notify({state:self.registration.active?'update_available':'ready',ready:true});
  }catch(error){await caches.delete(CACHE_NAME);await notify({state:'failed',ready:false,warning:error.message});throw error;}
})()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{
  for(const name of await caches.keys())if(name.startsWith('iqtadi-app-')&&name!==CACHE_NAME)await caches.delete(name);
  await self.clients.claim();await notify({ready:true,state:'ready'});
})()));
self.addEventListener('message',event=>{
  if(event.data?.type==='ACTIVATE_UPDATE')self.skipWaiting();
  if(event.data?.type==='OFFLINE_STATUS')event.waitUntil((async()=>{
    const cache=await caches.open(CACHE_NAME),manifest=await cache.match(new URL('iqtadi-offline-manifest.json',appBase()));
    if(manifest){const data=await manifest.json();await notify({ready:true,state:'ready',completed:data.files.length,total:data.files.length},event.source);}
    else await notify(installStatus,event.source);
  })());
});
self.addEventListener('fetch',event=>{
  const request=event.request,url=new URL(request.url),base=appBase();
  if(request.method!=='GET'||url.origin!==self.location.origin||!url.pathname.startsWith(base.pathname))return;
  const relative=url.pathname.slice(base.pathname.length);
  // Same-origin API services belong exclusively to Mosque Companion and remain
  // online; their requests/responses cannot become offline prayer assets.
  if(relative.startsWith('api/')||relative.startsWith('ws/')||relative.startsWith('healthz'))return;
  event.respondWith((async()=>{
    const cache=await caches.open(CACHE_NAME);
    // A complete app version is served consistently until an update is activated.
    const asset=await cache.match(new URL(relative||'index.html',base));
    if(asset)return asset;
    if(request.mode==='navigate'){const index=await cache.match(new URL('index.html',base));if(index)return index;}
    return fetch(request);
  })());
});
