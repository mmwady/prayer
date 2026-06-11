// ─────────────────────────────────────────────────────────────────────────────
// pose_detector_provider_stub.dart
//
// Native/Stub factory for PoseDetector.
// ─────────────────────────────────────────────────────────────────────────────

import 'pose_detector.dart';

/// Returns a default Native/Stub implementation.
PoseDetector getPlatformPoseDetector() {
  // We fall back to the StubPoseDetector used for emulator testing.
  // When native camera ML Kit is implemented, it can be swapped here.
  return StubPoseDetector();
}
