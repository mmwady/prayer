// ─────────────────────────────────────────────────────────────────────────────
// pose_detector.dart
//
// Pose-detection interface + a deterministic stub implementation.
//
// A detector now owns two things:
//   1. a stream of normalized skeleton keypoints for analysis
//   2. an optional preview widget for the real camera/video feed
//
// This lets the workout screen show a split view:
//   top    → skeleton / joints
//   bottom → real camera or uploaded video
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/keypoint.dart';

/// Contract every pose-detection backend must satisfy.
abstract class PoseDetector {
  /// Frames per second. The frontend overlay ties its animation refresh to
  /// whatever the detector produces, so this is effectively the UI tick rate.
  Stream<List<Keypoint>> get stream;

  /// Real visual source behind the pose stream.
  ///
  /// Mobile returns a CameraPreview, Web returns an HtmlElementView for the
  /// selected video, and the stub returns a placeholder.
  Widget buildPreview();

  Future<void> start();
  Future<void> stop();

  Future<void> dispose() => stop();
}

/// Optional preview geometry, shared by the live feed and its overlay.
abstract class PosePreviewGeometry {
  double get previewAspectRatio;
  bool get previewMirrored;
}

/// Canned animation useful when no real camera/video source is available.
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
  Widget buildPreview() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          'لا يوجد مصدر فيديو مباشر',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  @override
  Future<void> start() async {
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

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  void _emitFrame() {
    _frameIndex += 1;
    _phase = (_frameIndex / fps) * math.pi;
    final depth = (math.sin(_phase) + 1) / 2;

    final headY = 0.12;
    final shoulderY = 0.25 + 0.05 * depth;
    final hipY = 0.55 + 0.08 * depth;
    final kneeY = 0.70 + 0.10 * depth;
    final ankleY = 0.90;

    final faulted = (_frameIndex ~/ fps) % 4 == 3;
    final spineForwardBias = faulted ? 0.08 : 0.0;

    final keypoints = <Keypoint>[
      Keypoint(id: KeypointId.nose, x: 0.50, y: headY, confidence: 0.95),
      Keypoint(
          id: KeypointId.leftEye, x: 0.47, y: headY - 0.01, confidence: 0.9),
      Keypoint(
          id: KeypointId.rightEye, x: 0.53, y: headY - 0.01, confidence: 0.9),
      Keypoint(id: KeypointId.leftEar, x: 0.44, y: headY, confidence: 0.8),
      Keypoint(id: KeypointId.rightEar, x: 0.56, y: headY, confidence: 0.8),
      Keypoint(
          id: KeypointId.leftShoulder, x: 0.40, y: shoulderY, confidence: 0.95),
      Keypoint(
          id: KeypointId.rightShoulder,
          x: 0.60,
          y: shoulderY,
          confidence: 0.95),
      Keypoint(
          id: KeypointId.leftElbow,
          x: 0.36,
          y: shoulderY + 0.08,
          confidence: 0.9),
      Keypoint(
          id: KeypointId.rightElbow,
          x: 0.64,
          y: shoulderY + 0.08,
          confidence: 0.9),
      Keypoint(
          id: KeypointId.leftWrist,
          x: 0.34,
          y: shoulderY + 0.16,
          confidence: 0.85),
      Keypoint(
          id: KeypointId.rightWrist,
          x: 0.66,
          y: shoulderY + 0.16,
          confidence: 0.85),
      Keypoint(id: KeypointId.leftHip, x: 0.43, y: hipY, confidence: 0.95),
      Keypoint(id: KeypointId.rightHip, x: 0.57, y: hipY, confidence: 0.95),
      Keypoint(id: KeypointId.leftKnee, x: 0.42, y: kneeY, confidence: 0.9),
      Keypoint(id: KeypointId.rightKnee, x: 0.58, y: kneeY, confidence: 0.9),
      Keypoint(id: KeypointId.leftAnkle, x: 0.43, y: ankleY, confidence: 0.9),
      Keypoint(id: KeypointId.rightAnkle, x: 0.57, y: ankleY, confidence: 0.9),
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
