// Decode local video to sampled JPEGs. No ML, network or video upload here.
(() => {
  let video, url;
  let sourceId = 0;
  const wait = (target, event, start) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => finish(new Error('VIDEO_DECODE_TIMEOUT')), 15000);
    const finish = error => {
      clearTimeout(timer);
      target.removeEventListener(event, ok);
      target.removeEventListener('error', fail);
      error ? reject(error) : resolve();
    };
    const ok = () => finish();
    const fail = () => finish(new Error('VIDEO_DECODE_FAILED'));
    target.addEventListener(event, ok, { once: true });
    target.addEventListener('error', fail, { once: true });
    start();
  });
  window.iqtadiVideoClose = id => {
    if (id !== undefined && id !== sourceId) return;
    if (video) { video.pause(); video.removeAttribute('src'); video.load(); }
    if (url) URL.revokeObjectURL(url);
    video = url = null;
  };
  window.iqtadiVideoPick = async () => {
    const input = document.createElement('input');
    input.type = 'file'; input.accept = 'video/*';
    input.style.display = 'none';
    document.body.appendChild(input);
    const file = await new Promise(resolve => {
      input.onchange = () => resolve(input.files[0] || null);
      input.oncancel = () => resolve(null);
      input.click();
    });
    input.remove();
    if (!file) return 'null';
    window.iqtadiVideoClose();
    sourceId++;
    video = document.createElement('video'); video.preload = 'auto';
    video.muted = true; video.playsInline = true;
    url = URL.createObjectURL(file);
    await wait(video, 'loadeddata', () => { video.src = url; });
    if (!Number.isFinite(video.duration) || video.duration <= 0) throw new Error('INVALID_VIDEO_DURATION');
    return JSON.stringify({ name: file.name, duration_ms: Math.floor(video.duration * 1000), source_id: sourceId });
  };
  window.iqtadiVideoFrame = async (time, dimension, id) => {
    if (!video || id !== sourceId) throw new Error('NO_LOCAL_VIDEO');
    const target = time / 1000;
    if (Math.abs(video.currentTime - target) > 0.0001) {
      await wait(video, 'seeked', () => { video.currentTime = target; });
    }
    const canvas = document.createElement('canvas');
    const scale = Math.min(1, dimension / Math.max(video.videoWidth, video.videoHeight));
    canvas.width = Math.max(1, Math.round(video.videoWidth * scale));
    canvas.height = Math.max(1, Math.round(video.videoHeight * scale));
    // Browser decoding applies the video's display orientation.
    canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL('image/jpeg', 0.8).split(',')[1];
  };
})();
