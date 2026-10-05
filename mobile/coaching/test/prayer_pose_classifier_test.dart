import 'package:flutter_test/flutter_test.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/prayer/prayer_demo_detector.dart';
import 'package:coaching/prayer/prayer_pose_classifier.dart';

void main() {
  const classifier = PrayerPoseClassifier();
  for (final pose in PrayerPose.values) {
    test('synthetic ${pose.name} geometry', () {
      expect(classifier.classify(syntheticPrayerKeypoints(pose)).pose, pose);
    });
  }
  test(
      'missing, low-confidence, non-finite and degenerate joints return unknown',
      () {
    final points = syntheticPrayerKeypoints(PrayerPose.standing);
    expect(
        classifier.classify(points.take(3).toList()).pose, PrayerPose.unknown);
    expect(
        classifier
            .classify(points.map((p) => p.copyWith(confidence: 0.2)).toList())
            .pose,
        PrayerPose.unknown);
    expect(
        classifier
            .classify(points.map((p) => p.copyWith(x: double.nan)).toList())
            .pose,
        PrayerPose.unknown);
    expect(
        classifier
            .classify(points.map((p) => p.copyWith(x: 0.5, y: 0.5)).toList())
            .pose,
        PrayerPose.unknown);
    expect(
        classifier.classify(points.map((p) => p.copyWith(x: 2)).toList()).pose,
        PrayerPose.unknown);
  });
  test('horizontal mirroring preserves physical classes', () {
    for (final pose in PrayerPose.values) {
      final mirrored = syntheticPrayerKeypoints(pose)
          .map((p) => p.copyWith(x: 1 - p.x))
          .toList();
      expect(classifier.classify(mirrored).pose, pose);
    }
  });
}
