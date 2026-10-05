/* Camera pixels are sent only after Flutter's explicit consent/start action. */
(() => {
  const cameras = new Map(), sockets = new Map();
  let next = 0, wake = null;
  let storeDb;
  async function db() {
    if (!storeDb) storeDb = new Promise((resolve, reject) => {
      const request = indexedDB.open('iqtadi-live-frames', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('frames', {keyPath: ['session', 'index']});
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    return storeDb;
  }
  async function transaction(action) {
    const database = await db();
    return new Promise((resolve, reject) => {
      const tx = database.transaction('frames', 'readwrite');
      let result;
      action(tx.objectStore('frames'), value => { result = value; });
      tx.oncomplete = () => resolve(result);
      tx.onerror = tx.onabort = () => reject(tx.error || Error('LOCAL_STORAGE_FAILED'));
    });
  }
  window.iqtadiLive = {
    storageVersion: 1,
    async openStore() {
      // Expire abandoned records; active sessions remain isolated by session key.
      await transaction(store => {
        store.openCursor().onsuccess = event => {
          const cursor = event.target.result;
          if (!cursor) return;
          if (Date.now() - cursor.value.created > 3600000) cursor.delete();
          cursor.continue();
        };
      });
      return `${Date.now()}-${crypto.randomUUID()}`;
    },
    putFrame(session, index, bytes) {
      return transaction(store => store.put({session, index, bytes, created: Date.now()}));
    },
    readFrame(session, index) {
      return transaction((store, result) => {
        store.get([session, index]).onsuccess = event => result(event.target.result?.bytes);
      }).then(bytes => { if (!bytes) throw Error('LOCAL_FRAME_MISSING'); return bytes; });
    },
    removeFrame(session, index) { return transaction(store => store.delete([session, index])); },
    clearStore(session) {
      return transaction(store => {
        const range = IDBKeyRange.bound([session, 0], [session, Number.MAX_SAFE_INTEGER]);
        store.delete(range);
      });
    },
    async open(front = true, requireDirection = false) {
      if (!navigator.mediaDevices?.getUserMedia) throw Error('CAMERA_REQUIRES_HTTPS');
      const facing = front ? 'user' : 'environment';
      const stream = await navigator.mediaDevices.getUserMedia({audio: false,
        video: {facingMode: requireDirection ? {exact: facing} : {ideal: facing},
          width: {ideal: 640}, height: {ideal: 480}}});
      const video = document.createElement('video');
      video.muted = true; video.playsInline = true; video.autoplay = true;
      const mirrored = stream.getVideoTracks()[0].getSettings().facingMode === 'user' ||
        (!stream.getVideoTracks()[0].getSettings().facingMode && front);
      video.style.cssText = `width:100%;height:100%;object-fit:contain;background:#000;transform:scaleX(${mirrored ? -1 : 1})`;
      video.srcObject = stream;
      try { await video.play(); }
      catch (error) { stream.getTracks().forEach(t => t.stop()); throw error; }
      const id = ++next;
      cameras.set(id, {video, stream, canvas: document.createElement('canvas')});
      return id;
    },
    video(id) { return cameras.get(id).video; },
    async frame(id, dimension) {
      const c = cameras.get(id), v = c?.video;
      if (!v || v.readyState < 2 || !v.videoWidth ||
          c.stream.getVideoTracks().some(t => t.readyState !== 'live' || t.muted)) {
        throw Error('CAMERA_INTERRUPTED');
      }
      const scale = Math.min(1, dimension / Math.max(v.videoWidth, v.videoHeight));
      c.canvas.width = Math.max(1, Math.round(v.videoWidth * scale));
      c.canvas.height = Math.max(1, Math.round(v.videoHeight * scale));
      // Preview is mirrored; transmitted pixels preserve the camera's direction.
      c.canvas.getContext('2d').drawImage(v, 0, 0, c.canvas.width, c.canvas.height);
      return c.canvas.toDataURL('image/jpeg', .8).split(',')[1];
    },
    closeCamera(id) {
      const c = cameras.get(id);
      if (c) { c.stream.getTracks().forEach(t => t.stop()); c.video.srcObject = null; cameras.delete(id); }
    },
    async awake(enabled) {
      if (!enabled) { if (wake) await wake.release(); wake = null; return true; }
      try { wake = await navigator.wakeLock.request('screen'); return true; }
      catch (_) { return false; }
    },
    connect(url, token) {
      return new Promise((resolve, reject) => {
        const id = ++next, socket = new WebSocket(url);
        const state = {socket, pending: null}; sockets.set(id, state);
        const timer = setTimeout(() => { socket.close(); sockets.delete(id); reject(Error('LIVE_CONNECT_TIMEOUT')); }, 90000);
        socket.onopen = () => socket.send(JSON.stringify({token}));
        socket.onmessage = event => {
          const data = JSON.parse(event.data);
          if (data.type === 'ready') { clearTimeout(timer); resolve(JSON.stringify({socket_id: id, ...data})); }
          else if (state.pending) { const p = state.pending; state.pending = null; clearTimeout(p.timer); p.resolve(event.data); }
          else if (data.type === 'error') { clearTimeout(timer); socket.close(); sockets.delete(id); resolve(event.data); }
        };
        const failed = () => {
          clearTimeout(timer); reject(Error('LIVE_DISCONNECTED'));
          if (state.pending) { clearTimeout(state.pending.timer); state.pending.reject(Error('LIVE_DISCONNECTED')); state.pending = null; }
        };
        socket.onerror = failed; socket.onclose = failed;
      });
    },
    send(id, bytes) {
      return new Promise((resolve, reject) => {
        const state = sockets.get(id);
        if (!state || state.socket.readyState !== WebSocket.OPEN || state.pending) return reject(Error('LIVE_DISCONNECTED'));
        const timer = setTimeout(() => {
          state.pending = null; state.socket.close(); reject(Error('LIVE_ACK_TIMEOUT'));
        }, 30000);
        state.pending = {resolve, reject, timer};
        state.socket.send(bytes);
      });
    },
    closeSocket(id) { const s = sockets.get(id); if (s) { s.socket.close(); sockets.delete(id); } }
  };
})();
