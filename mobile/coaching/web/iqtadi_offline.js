// The service worker caches static app/model assets only. User images, video,
// predictions and Mosque Companion API responses are never placed in this cache.
(() => {
  let state={ready:false,state:'preparing',completed:0,total:0,version:null},registration;
  const publish=value=>{state={...state,...value};window.dispatchEvent(new CustomEvent('iqtadi-offline-status',{detail:state}));};
  window.iqtadiOffline=Object.freeze({status:()=>({...state}),
    applyUpdate:async()=>{
      if(!registration?.waiting)return false;
      await new Promise((resolve,reject)=>{
        const changed=()=>{clearTimeout(timer);resolve();};
        const timer=setTimeout(()=>{navigator.serviceWorker.removeEventListener('controllerchange',changed);reject(Error('Offline update did not activate; close other tabs and retry.'));},45000);
        navigator.serviceWorker.addEventListener('controllerchange',changed,{once:true});
        registration.waiting.postMessage({type:'ACTIVATE_UPDATE'});
      });
      // User explicitly requested the update. Reload both Flutter and the shared
      // inference bridge together, before any new-version assets are consumed.
      window.location.reload();return true;
    },
    requestPersistence:async()=>navigator.storage?.persist ? navigator.storage.persist() : false});
  if (!('serviceWorker' in navigator) || !window.isSecureContext) {publish({state:'unavailable',warning:'Offline storage requires HTTPS or localhost.'});return;}
  navigator.serviceWorker.addEventListener('message',({data})=>{if(data?.source==='iqtadi-offline')publish(data.status);});
  navigator.serviceWorker.register(new URL('iqtadi_service_worker.js',document.baseURI),
    {scope:new URL('./',document.baseURI).pathname,updateViaCache:'none'}).then(async value=>{
    registration=value;
    const worker=value.active ?? value.installing ?? value.waiting;
    worker?.postMessage({type:'OFFLINE_STATUS'});
    if(value.waiting)publish({state:'update_available',ready:!!value.active});
    value.addEventListener('updatefound',()=>{const next=value.installing;next?.addEventListener('statechange',()=>{
      if(next.state==='installed'&&value.waiting&&value.active)publish({state:'update_available',ready:true});
      if(next.state==='redundant')publish({state:'failed',ready:false,warning:'Offline download did not complete. Inference can still run online.'});
    });});
    const ready=await navigator.serviceWorker.ready;ready.active?.postMessage({type:'OFFLINE_STATUS'});
  }).catch(error=>publish({state:'unavailable',warning:error.message}));
})();
