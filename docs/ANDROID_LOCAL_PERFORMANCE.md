# Android local inference performance

Device: Samsung M52 (SM-M526BR), Android 13/API 33, ARM64. Measurements on
2026-10-05 use USB-connected hardware, not an emulator. Test assets and results
stay on the computer/device; the production APK does not contain the 100 test
images. No inference endpoint or networking was added.

## Quality constraints

The Heavy pose task, three ONNX classifiers, float32 normalization, Pillow-compatible
RGB/letterbox/recovery transforms, class ordering, individual softmax and class-wise
probability mean are unchanged. CPU IMAGE mode and detection/presence/tracking
thresholds 0.2 remain the defaults. Live automatic capture still requires three
stable confident matches; classification confidence does not establish prayer validity.

Changes remove avoidable work: a single bounded RAM frame in local adaptive live
mode; direct StandardMessageCodec map conversion instead of JSON round-tripping;
one immutable ONNX input tensor reused across three independent sessions; a bounded
12-entry cache of exactly the same Lanczos coefficients; and evidence rendering
only for selected representative/stable-capture frames. Buffered mode retains its
existing storage. A serialized native executor and live backpressure prevent
overlapping inference. Deferred evidence uses a matching token and cancellation
generation checks.

## Physical comparison

The corpus contains 100 real JPEG frames covering all eight classes, including one
undetected pose. Files are every second lexically sorted frame from the existing
200-frame real-video corpus, with the final selection replaced by video_1_097.jpg.
Each run warms up three times. The harness records all 166 features, all individual
decisions/probabilities, recovery, and the SHA-256 of the rendered evidence JPEG.
No test data is posted to a server.

The baseline CPU debug build averages 1283.85 ms/frame, median 1472.89 ms and p90
1997.11 ms. These timings include JPEG decoding, preprocessing, detection, three
classifiers and evidence rendering; they exclude camera encoding and Dart overhead.

Experimental GPU Heavy detection averaged 1086.79 ms/frame (15.35% faster), but
changed 9/100 ensemble decisions and recovery choices. It is **rejected for the
shipping app**. CPU remains the default. See `output/android-performance/gpu-comparison.json`.

Final release CPU completed all 100 cases. All predictions (apart from timings),
166-feature vectors and evidence JPEG hashes match exactly, including the same
undetected case. Maximum feature/probability error is **0.0**. Every result has
three individual model slots; every valid ensemble is their probability mean and
its displayed decision is the maximum averaged probability.
There are 99 valid poses and one explicit failed pose. In 17 valid cases at least
one classifier differs from the ensemble; those individual decisions remain in
the result. Recovery counts: 93 standard, three contrast 1.15, two rotation -5,
one rotation +5, one failed. Initialization takes 708.90 ms in the final run.

| Measured path | Mean | Median | p90 |
|---|---:|---:|---:|
| Baseline debug CPU, including every preview |1283.85 ms|1472.89 ms|1997.11 ms|
| Optimized release CPU prediction, before preview |534.80 ms|439.53 ms|585.74 ms|
| Optimized release CPU, including every preview |545.66 ms|452.92 ms|591.45 ms|

The full native path, including all previews, is **57.50% faster in this run**;
the prediction path alone takes 58.34% less time. Preview rendering averages
10.86 ms and is omitted only when that frame is not retained as evidence.
This is debug-versus-release, not an isolated optimization A/B attribution or
a guaranteed frame rate. Evidence: `output/android-performance/cpu-comparison.json`,
`baseline.json` and `optimized-deferred.json` in the same directory.

The verified release APK is `mobile/coaching/build/app/outputs/flutter-apk/iqtadi-local-optimized-arm64.apk`,
201,817,692 bytes, SHA-256
`66fbbb60f4e841728eb7683a5f3bf116d079c73eee962d6b8cd213136056bd49`.
All six required asset hashes match the original export manifest; the APK contains
no test JPEGs. It was installed as an update preserving application data. The existing
debug signing key is retained for local installation; this is not store release signing.

## Automated checks

- 111/111 Flutter tests pass, including deferred preview selection/cancellation,
  camera-owned byte copying, bounded frame storage and native codec double preservation.
- 6/6 Kotlin parity tests pass: 263 landmark feature goldens and 20 exact image
  transformation goldens, plus existing inference/report mathematics.
- `flutter analyze --no-pub`: zero errors/warnings, six pre-existing informational
  diagnostics in legacy geometry code.

## Release initialization

Physical tests exposed R8-only MediaPipe failures: Protobuf reflective fields,
Flogger stack discovery, serialized JNI packet fields, Packet factories, callback
`process()` dispatch, and ONNX Runtime Java value factories must be retained.
`android/app/proguard-rules.pro` keeps those boundaries
without disabling application shrinking or changing inference.
The [official Protobuf Lite guidance](https://github.com/protocolbuffers/protobuf/blob/main/java/lite.md)
documents reflective fields; [Flogger's factory source](https://github.com/google/flogger/blob/master/api/src/main/java/com/google/common/flogger/FluentLogger.java)
documents stack-dependent caller discovery. [ONNX Runtime's Android documentation](https://onnxruntime.ai/docs/build/android.html)
requires retaining `ai.onnxruntime.**` for R8 builds. Runtime validation, not build success,
is the acceptance gate.

## Reproduction and limits

From `mobile/coaching/android`, place the selected local JPEGs under
`../build/inference-fixtures/inference/` (androidTest assets only), then run:

```powershell
./gradlew.bat :app:assembleRelease :app:assembleReleaseAndroidTest `
  '-PiqtadiTestRunner=com.example.coaching.LocalInferenceBenchmarkInstrumentation' `
  '-PiqtadiTestBuildType=release' '-Ptarget-platform=android-arm64'
adb install --no-streaming -r ../build/app/outputs/apk/release/app-release.apk
adb install --no-streaming -r ../build/app/outputs/apk/androidTest/release/app-release-androidTest.apk
adb shell am instrument -w -e label optimized_deferred `
  com.example.coaching.test/com.example.coaching.LocalInferenceBenchmarkInstrumentation
```

Pull the app-external `inference-optimized_deferred.json` to the local evidence
directory and compare with `compare_inference_benchmarks.py`. Remove these test
JSON files from the phone after pulling. The deferred benchmark deliberately renders
every preview to establish quality parity; actual sessions render selected evidence.

Sequential device runs are affected by charging, temperature, JIT/AOT compilation
and other device work. Debug-versus-release results measure the complete build
change, not the isolated contribution of each optimization. Camera/photos/live UI,
SAF export and other devices remain unverified unless explicitly recorded below.
No claim of Safari, Firefox or WebGPU verification is made.
