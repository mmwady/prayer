# Android sequential video extraction

Android now keeps one decoder open for the selected video and moves forward through
its presentation timestamps. Unsampled frames are released without rendering. Only
selected frames reach the GPU scaling/readback surface and JPEG encoding.

## Preserved contracts

- Existing `pick`, `frame`, `close` method channel, selected-source IDs and Arabic errors.
- Backend-selected sampling interval, dimension limit, JPEG quality 80 and byte limit.
- Requested timestamps/sequence indices, consent, batching, upload, cancellation,
  polling, reports and backend inference. No Dart, web or backend implementation changed.
- Closest-frame selection, including later-frame ties, final-frame reuse and low-FPS clips.
- Rotation 0/90/180/270, aspect ratio, no upscaling, bounded memory and decoder cleanup.
- A backward timestamp (retry) or changed dimension restarts the decoder. Ordinary
  forward requests and upload pauses reuse it.
- If codec/surface initialization or decoding fails, the bridge releases the decoder
  and uses the original retriever for the remaining selection. A new selection resets
  this fallback. HDR transfer functions retain the original tone-mapping path.

This does not promise identical JPEG bytes: GPU and retriever interpolation/color
conversion can differ slightly. Native tests compare image geometry and sampled RGB
pixels, not compressed byte equality. No extraction change proves model accuracy.

## Device evidence (2026-10-04)

Samsung SM-M526BR (M52), Android 13 / API 33. Synthetic local H.264 fixtures only;
no uploaded user videos, backend requests, model inference or paid providers.

| Fixture | Samples | New extraction (ms) | Retriever (ms) |
| --- | ---: | ---: | ---: |
| 8-second 1920x1080, 30 FPS, 240-frame GOP | 34 | 2681 | 39649 |
| Same video, 90-degree rotation | 34 | 2818 | 46833 |
| Same video, 270-degree rotation | 34 | 2798 | 42754 |
| Same video, 180-degree rotation | 34 | 2831 | 45100 |
| 640x360, 2 FPS | 14 | 286 | 1837 |
| 640x360, variable FPS | 14 | 478 | 2227 |
| 640x360, reordered B-frames | 15 | 630 | 2462 |

Measurements include decoder setup in the new extraction time and interleave old/new
requests for each timestamp. JPEG compression, upload and pixel comparison are excluded.
Samples include repeated initial timestamps and the end-of-video boundary in addition
to ordinary 250ms sampling. Large GOPs deliberately exercise costly repeated seeks;
these improvements are not a guaranteed multiplier for other videos/devices.

All seven fixture cases passed dimension/orientation, image similarity, valid JPEG
and 200KB transport-limit checks. Early close/retry/resize passed. App-targeted
instrumentation additionally launched the actual Flutter activity and checked its
forward decoder reuse, backward-request restart, dimension restart and persistent
retriever fallback after an injected initialization failure.

The complete Flutter suite passed 61 tests. `flutter analyze --no-pub` reported six
existing infos and no errors/warnings. Both native app and instrumentation compiled.

## Reproduce

Requires a connected Android device, Android/Flutter build tools and FFmpeg on PATH.
From `mobile/coaching/android`:

```powershell
./generate_extraction_fixtures.ps1
./gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest
adb install -r ../build/app/outputs/apk/debug/app-debug.apk
adb install -r ../build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w com.example.coaching.test/com.example.coaching.ExtractionInstrumentation
```

For one fixture plus lifecycle checks, pass `-e clip bframes.mp4` before the runner.
Fixture generation writes only ignored `build/extraction-fixtures`; no test media is
bundled into the production app. The instrumentation uses temporary app cache files.
`IqtadiVideo` debug logs contain sample counts and cumulative extraction/JPEG time,
without filenames, images, tokens or payloads.
