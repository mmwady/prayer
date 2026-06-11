// ─────────────────────────────────────────────────────────────────────────────
// pose_detector_provider.dart
//
// Conditionally exports the correct PoseDetector factory based on the 
// compilation target (Web vs. Non-Web).
// ─────────────────────────────────────────────────────────────────────────────

export 'pose_detector_provider_stub.dart'
    if (dart.library.html) 'pose_detector_provider_web.dart'
    if (dart.library.io) 'pose_detector_provider_mobile.dart';
