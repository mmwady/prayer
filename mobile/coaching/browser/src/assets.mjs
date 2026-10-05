import { SCHEMA_VERSION, CLASSES } from './core.mjs';
export async function manifestAt(base) {
  const url = new URL('assets/manifest.json',base),cacheName='iqtadi-manifest-'+SCHEMA_VERSION;
  let cache,response;
  try { if (globalThis.caches) cache=await caches.open(cacheName); } catch { /* Optional persistent cache. */ }
  try { response = await fetch(url, { cache: 'no-cache' }); }
  catch (error) { response = await cache?.match(url); if (!response) throw Error('Model manifest unavailable offline: complete the first download'); }
  if (!response.ok) throw Error('Model manifest unavailable');
  const manifest = await response.clone().json();
  if (manifest.schema_version !== SCHEMA_VERSION || JSON.stringify(manifest.classes) !== JSON.stringify(CLASSES)) {
    try { await cache?.delete(url); } catch { /* Denied storage is reported by callers. */ }
    throw Error('Schema/class order mismatch: rebuild the application and assets together');
  }
  try { await cache?.put(url,response); } catch { /* Storage denied: online inference still works. */ }
  return manifest;
}
export async function cachedAsset(base, name, manifest, onProgress = () => {}) {
  const expected = manifest.assets[name];
  if (!expected) throw Error('Unversioned model asset: ' + name);
  const url = new URL('assets/' + name, base); url.searchParams.set('v', expected);
  const cacheName = 'iqtadi-models-' + manifest.model_version;
  let cache;
  try { if (globalThis.caches) cache = await caches.open(cacheName); } catch { /* Private browsing: normal HTTP cache. */ }
  let response = await cache?.match(url);
  if (!response) { response = await fetch(url, { cache: 'default' }); if (!response.ok) throw Error('Missing asset: ' + name); }
  const total = Number(response.headers.get('content-length')) || 0;
  let bytes;
  if (response.body?.getReader) {
    const reader = response.body.getReader(), chunks = [];
    let loaded = 0, lastProgress = 0;
    onProgress({ phase: 'downloading', asset: name, loaded, total });
    try {
      while (true) {
        // A stalled connection fails explicitly; total download time is unlimited.
        let timer;
        const stalled = new Promise((_, reject) => { timer = setTimeout(() => reject(Error('Model download stalled: ' + name)), 60000); });
        let part;
        try { part = await Promise.race([reader.read(), stalled]); }
        finally { clearTimeout(timer); }
        if (part.done) break;
        chunks.push(part.value); loaded += part.value.byteLength;
        if (Date.now() - lastProgress >= 150) {
          onProgress({ phase: 'downloading', asset: name, loaded, total }); lastProgress = Date.now();
        }
      }
      const joined = new Uint8Array(loaded); let offset = 0;
      for (const chunk of chunks) { joined.set(chunk, offset); offset += chunk.byteLength; }
      bytes = joined.buffer;
    } catch (error) { await reader.cancel().catch(() => {}); throw error; }
    finally { reader.releaseLock(); }
  } else { bytes = await response.arrayBuffer(); }
  onProgress({ phase: 'verifying', asset: name, loaded: bytes.byteLength, total: bytes.byteLength });
  const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), x => x.toString(16).padStart(2, '0')).join('');
  if (digest !== expected) { await cache?.delete(url); throw Error('Model asset hash mismatch: ' + name); }
  try { await cache?.put(url, new Response(bytes)); } catch { /* Quota/storage denied: inference still works. */ }
  return bytes;
}
export async function purgeOldAssets(version) {
  try { for (const name of await caches.keys()) if (name.startsWith('iqtadi-models-') && name !== 'iqtadi-models-' + version) await caches.delete(name); } catch { /* Optional cache. */ }
}
