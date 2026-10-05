import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coaching/models/keypoint.dart';
import 'package:coaching/services/pose_detector.dart';
import 'package:coaching/state/prayer_controller.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/prayer/prayer_demo_detector.dart';
import 'package:coaching/prayer/prayer_sequence_engine.dart';

class TestDetector extends PoseDetector {
  final frames = StreamController<List<Keypoint>>.broadcast(sync: true);
  bool failStart = false, released = false;
  Completer<void>? startup;
  @override
  Stream<List<Keypoint>> get stream => frames.stream;
  @override
  Widget buildPreview() => const SizedBox();
  @override
  Future<void> start() async {
    if (failStart) throw StateError('No camera');
    await startup?.future;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    released = true;
    await frames.close();
  }
}

void main() {
  test('source failures are visible and retryable', () async {
    final detector = TestDetector()..failStart = true;
    final c = PrayerController(
        definition: PrayerCatalog.of(PrayerType.demo), detector: detector);
    await c.start();
    expect(c.sourceError, isNotNull);
    expect(c.started, false);
    expect(c.state.completedStations, isEmpty);
    detector.failStart = false;
    await c.start();
    expect(c.started, true);
    c.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(detector.released, true);
  });

  test('missing stream frames produce uncertainty, not progress', () async {
    var now = DateTime(2026);
    final detector = TestDetector();
    final c = PrayerController(
        definition: PrayerCatalog.of(PrayerType.demo),
        detector: detector,
        clock: () => now);
    await c.start();
    detector.frames.add(syntheticPrayerKeypoints(PrayerPose.standing));
    now = now.add(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(c.state.feedback, MovementFeedback.lowConfidence);
    expect(c.state.lowConfidenceEvents, 1);
    expect(c.keypoints, isEmpty);
    expect(c.state.completedStations, isEmpty);
    c.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('leaving during asynchronous detector startup releases resources',
      () async {
    final detector = TestDetector()..startup = Completer<void>();
    final c = PrayerController(
        definition: PrayerCatalog.of(PrayerType.demo), detector: detector);
    final pending = c.start();
    c.dispose();
    detector.startup!.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(detector.released, true);
  });
}
