// Backward-compatible legacy calibration bridge, using the same local Heavy
// detector. No CDN, model-input upload, or fabricated 3D world coordinates.
(() => {
  const ready = () => window.iqtadiLocal ? Promise.resolve() : new Promise((resolve,reject) => {
    const timer=setTimeout(()=>{window.removeEventListener('iqtadi-local-ready',done);reject(Error('LOCAL_ENGINE_NOT_LOADED'));},30000);
    const done=()=>{clearTimeout(timer);resolve();};window.addEventListener('iqtadi-local-ready',done,{once:true});
  });
  window.initMediaPipePose = async () => { await ready();await window.iqtadiLocal.initialize(); };
  window.estimatePose = async source => { await ready();return window.iqtadiLocal.estimatePose(source); };
})();
