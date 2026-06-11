// mediapipe_wrapper.js
// Provides an easy promise-based async interface for dart:js_interop

let poseDetector = null;

// Initialization function
async function initMediaPipePose() {
  if (poseDetector) return;

  poseDetector = new window.Pose({
    locateFile: (file) => {
      return `https://cdn.jsdelivr.net/npm/@mediapipe/pose/${file}`;
    }
  });

  poseDetector.setOptions({
    modelComplexity: 1, // 0 = lite, 1 = full, 2 = heavy
    smoothLandmarks: true,
    enableSegmentation: false,
    smoothSegmentation: false,
    minDetectionConfidence: 0.5,
    minTrackingConfidence: 0.5
  });

  // Since we are using an asynchronous send() call in Dart, 
  // we can resolve promises in onResults.
  poseDetector.onResults((results) => {
    if (window._mediapipeResolve) {
      window._mediapipeResolve(results.poseLandmarks || []);
      window._mediapipeResolve = null;
    }
  });

  // Init model (MediaPipe asynchronously loads WASM payload here)
  await poseDetector.initialize();
  console.log("MediaPipe Pose Initialized");
}

// Inference function
// We attach the promise resolve to window so the callback from onResults can trigger it.
async function estimatePose(videoElement) {
  if (!poseDetector) {
    await initMediaPipePose();
  }

  return new Promise((resolve, reject) => {
    window._mediapipeResolve = resolve;

    poseDetector.send({ image: videoElement }).catch((e) => {
      console.error("Pose processing failed:", e);
      window._mediapipeResolve = null;
      resolve([]); // return empty rather than crashing the pipeline
    });
  });
}

// Expose strictly to window
window.initMediaPipePose = initMediaPipePose;
window.estimatePose = estimatePose;
