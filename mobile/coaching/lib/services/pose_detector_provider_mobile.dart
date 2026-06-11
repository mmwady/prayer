// ─────────────────────────────────────────────────────────────────────────────
// pose_detector_provider_mobile.dart
//
// Native factory for PoseDetector.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'pose_detector.dart';
import 'mobile_pose_detector.dart';

/// Returns the ML Kit camera detector only on Android/iOS.
///
/// Conditional imports route every `dart:io` platform here, including Windows,
/// Linux, and macOS. The camera/ML Kit implementation is only wired for mobile
/// targets, so desktop uses the deterministic stub instead.
PoseDetector getPlatformPoseDetector() {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return StubPoseDetector();
  }

  return MobilePoseDetector(fps: 30);
}
