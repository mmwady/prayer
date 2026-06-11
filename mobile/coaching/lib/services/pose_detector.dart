// ─────────────────────────────────────────────────────────────────────────────
// pose_detector.dart
//
// Pose-detection interface + a deterministic stub implementation.
//
// The stub exists so the rest of the app (AR overlay, WebSocket, audio) can
// be developed, demoed, and tested without a running MediaPipe model. In
// production, a second implementation of [PoseDetector] wraps either
// `google_mlkit_pose_detection` or a MediaPipe Tasks platform channel and
// is injected in place of [StubPoseDetector] — nothing else changes.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import '../models/keypoint.dart';

/// Contract every pose-detection backend must satisfy.
///
/// Emitting a [Stream] (rather than a pull-based iterator) mirrors how
/// camera frames are produced on native platforms and plays well with
/// [StreamBuilder] in the overlay widget.
abstract class PoseDetector {
  /// Frames per second. The frontend overlay ties its animation refresh to
  /// whatever the detector produces, so this is effectively the UI tick rate.
  Stream<List<Keypoint>> get stream;

  Future<void> start();
  Future<void> stop();
}

/// Canned squat animation with an intentional "curved back" fault every 4s.
///
/// Useful for:
///   • Smoke-testing the end-to-end pipeline on an emulator with no camera.
///   • UI screenshots / demos at conferences (no PII in frame, no model IP).
///   • Deterministic integration tests where frame timing matters.
class StubPoseDetector implements PoseDetector {
  StubPoseDetector({this.fps = 30});

  final int fps;

  final StreamController<List<Keypoint>> _controller =
      StreamController<List<Keypoint>>.broadcast();
  Timer? _timer;
  double _phase = 0.0;
  int _frameIndex = 0;

  @override
  Stream<List<Keypoint>> get stream => _controller.stream;

  @override
  Future<void> start() async {
    // Drive the animation off a periodic timer — cheap, predictable, and
    // decoupled from the Flutter render ticker so the stream can be consumed
    // off-screen during tests.
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / fps).round()),
      (_) => _emitFrame(),
    );
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// Mutable internal state needed to animate a squat cycle. We generate
  /// keypoints in normalized 0..1 image space with the subject centered.
  void _emitFrame() {
    _frameIndex += 1;
    // A squat cycle takes ~2s; sine wave gives us a smooth down-and-up.
    _phase = (_frameIndex / fps) * math.pi; // half-cycle per second.
    final depth = (math.sin(_phase) + 1) / 2; // 0 (stand) .. 1 (bottom).

    // Key vertical positions. Numbers picked to look roughly like a person.
    final headY = 0.12;
    final shoulderY = 0.25 + 0.05 * depth;
    final hipY = 0.55 + 0.08 * depth;
    final kneeY = 0.70 + 0.10 * depth;
    final ankleY = 0.90;

    // Every 4 seconds, inject a "curved back" fault — shift the spine mid
    // forward relative to the hip/shoulder line. The form analyzer will
    // pick this up and fire a PoseEvent.
    final bool faulted = (_frameIndex ~/ fps) % 4 == 3;
    final spineForwardBias = faulted ? 0.08 : 0.0;

    final keypoints = <Keypoint>[
      Keypoint(id: KeypointId.nose, x: 0.50, y: headY, confidence: 0.95),
      Keypoint(id: KeypointId.leftEye, x: 0.47, y: headY - 0.01, confidence: 0.9),
      Keypoint(id: KeypointId.rightEye, x: 0.53, y: headY - 0.01, confidence: 0.9),
      Keypoint(id: KeypointId.leftEar, x: 0.44, y: headY, confidence: 0.8),
      Keypoint(id: KeypointId.rightEar, x: 0.56, y: headY, confidence: 0.8),
      Keypoint(id: KeypointId.leftShoulder, x: 0.40, y: shoulderY, confidence: 0.95),
      Keypoint(id: KeypointId.rightShoulder, x: 0.60, y: shoulderY, confidence: 0.95),
      Keypoint(id: KeypointId.leftElbow, x: 0.36, y: shoulderY + 0.08, confidence: 0.9),
      Keypoint(id: KeypointId.rightElbow, x: 0.64, y: shoulderY + 0.08, confidence: 0.9),
      Keypoint(id: KeypointId.leftWrist, x: 0.34, y: shoulderY + 0.16, confidence: 0.85),
      Keypoint(id: KeypointId.rightWrist, x: 0.66, y: shoulderY + 0.16, confidence: 0.85),
      Keypoint(id: KeypointId.leftHip, x: 0.43, y: hipY, confidence: 0.95),
      Keypoint(id: KeypointId.rightHip, x: 0.57, y: hipY, confidence: 0.95),
      Keypoint(id: KeypointId.leftKnee, x: 0.42, y: kneeY, confidence: 0.9),
      Keypoint(id: KeypointId.rightKnee, x: 0.58, y: kneeY, confidence: 0.9),
      Keypoint(id: KeypointId.leftAnkle, x: 0.43, y: ankleY, confidence: 0.9),
      Keypoint(id: KeypointId.rightAnkle, x: 0.57, y: ankleY, confidence: 0.9),
      // Spine mid derived from shoulders + hips, with optional faulted bias.
      Keypoint(
        id: KeypointId.spineMid,
        x: 0.50 + spineForwardBias,
        y: (shoulderY + hipY) / 2,
        confidence: 0.9,
      ),
    ];

    _controller.add(keypoints);
  }
}
