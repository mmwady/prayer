import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coaching/models/keypoint.dart';
import 'package:coaching/prayer/prayer_calibration.dart';
import 'package:coaching/prayer/prayer_reference.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/services/camera_pose_geometry.dart';
import 'helpers/prayer_reference_fixture.dart';
import 'package:coaching/prayer/prayer_floor_check.dart';
import 'package:coaching/prayer/prayer_demo_detector.dart';

void main() {
  test('motion restarts the continuous standing hold', () {
    final c = PrayerCalibration(calibrationReference());
    var now = DateTime(2026);
    for (var i = 0; i < 10; i++) {
      c.observe(calibrationPoints(), 1, now);
      now = now.add(const Duration(milliseconds: 100));
    }
    c.observe(calibrationPoints().map((p) => p.copyWith(x: p.x + .06)).toList(),
        1, now);
    expect(c.reading.progress, 0);
    expect(c.isReady(now), isFalse);
  });

  test('optional floor probe needs head and full visible side, ordered holds',
      () {
    final probe = PrayerFloorCheck()..start();
    var now = DateTime(2026);
    final ruku = syntheticPrayerKeypoints(PrayerPose.ruku);
    for (var i = 0; i < 12; i++) {
      probe.observe(ruku, 1, now);
      now = now.add(const Duration(milliseconds: 100));
    }
    expect(probe.phase, FloorCheckPhase.ruku);
    for (final pose in [PrayerPose.ruku, PrayerPose.sujood]) {
      for (var i = 0; i < 10; i++) {
        probe.observe([
          ...syntheticPrayerKeypoints(pose),
          const Keypoint(id: KeypointId.nose, x: .2, y: .6, confidence: .9)
        ], 1, now);
        now = now.add(const Duration(milliseconds: 100));
      }
    }
    expect(probe.phase, FloorCheckPhase.completed);
  });
  test(
      'ready needs a fresh continuous hold and resets immediately on bad input',
      () {
    final c = PrayerCalibration(calibrationReference());
    var now = DateTime(2026);
    for (var i = 0; i < 16; i++) {
      c.observe(calibrationPoints(), 1, now);
      now = now.add(const Duration(milliseconds: 100));
    }
    expect(c.isReady(now), isTrue);
    expect(c.isReady(now.add(const Duration(seconds: 1))), isFalse);
    c.observe([], 1, now);
    expect(c.reading.issue, CalibrationIssue.noBody);
    expect(c.isReady(now), isFalse);
    c.observe(
        calibrationPoints(), 1, now.add(const Duration(milliseconds: 100)));
    expect(c.reading.issue, CalibrationIssue.holding);
  });

  test('frame gaps and repeated timestamps cannot accumulate readiness', () {
    final c = PrayerCalibration(calibrationReference());
    var now = DateTime(2026);
    for (var i = 0; i < 20; i++) {
      c.observe(calibrationPoints(), 1, now);
    }
    expect(c.reading.ready, isFalse);
    now = now.add(const Duration(seconds: 2));
    c.observe(calibrationPoints(), 1, now);
    expect(c.reading.progress, 0);
    expect(c.reading.ready, isFalse);
  });

  test(
      'reject missing, nonfinite and weak joints; distinguish framing and angle',
      () {
    final c = PrayerCalibration(calibrationReference());
    final p = calibrationPoints();
    expect(c.check(p.skip(1).toList(), 1), CalibrationIssue.visibility);
    expect(c.check([p.first.copyWith(confidence: .1), ...p.skip(1)], 1),
        CalibrationIssue.visibility);
    expect(c.check([p.first.copyWith(x: double.nan), ...p.skip(1)], 1),
        CalibrationIssue.visibility);
    expect(c.check(p.map((x) => x.copyWith(x: x.x + .4)).toList(), 1),
        CalibrationIssue.framing);
    expect(c.check(calibrationPoints(shoulderSpread: .06, hipSpread: .04), 1),
        CalibrationIssue.angle);
    expect(c.check(calibrationPoints(noseX: .65), 1), CalibrationIssue.angle);
    expect(c.check(p, 1), isNull);
  });

  test('distance, center and posture have independent corrections', () {
    final c = PrayerCalibration(calibrationReference());
    final p = calibrationPoints();
    expect(
        c.check(p.map((p) => p.copyWith(y: .5 + (p.y - .5) * .6)).toList(), 1),
        CalibrationIssue.tooFar);
    expect(c.check(p.map((p) => p.copyWith(x: p.x + .15)).toList(), 1),
        CalibrationIssue.center);
    expect(
        c.check(
            p
                .map(
                    (p) => p.id == KeypointId.leftKnee ? p.copyWith(x: .72) : p)
                .toList(),
            1),
        CalibrationIssue.posture);
  });

  test(
      'aspect-corrected matching ignores frame dimensions and body translation',
      () {
    final matcher = PrayerReferenceMatcher(calibrationReference());
    final p = calibrationPoints();
    expect(matcher.distance(p, PrayerStation.standing), closeTo(0, 1e-8));
    final portrait =
        p.map((p) => p.copyWith(x: .5 + (p.x - .5) / .75)).toList();
    expect(matcher.distance(portrait, PrayerStation.standing, aspectRatio: .75),
        closeTo(0, 1e-8));
    final translated =
        p.map((p) => p.copyWith(x: p.x + .05, y: p.y - .03)).toList();
    expect(
        matcher.distance(translated, PrayerStation.standing), closeTo(0, 1e-8));
    expect(matcher.distance([], PrayerStation.standing), double.infinity);
  });

  test('depth spaces are retained without affecting projected calibration', () {
    final p = calibrationPoints()
        .map((p) => p.copyWith(
            position3d:
                const PosePoint3d(10, 20, 30, Pose3dSpace.mlkitImagePixels)))
        .toList();
    expect(PrayerCalibration(calibrationReference()).check(p, 1), isNull);
    expect(p.first.position3d!.space, Pose3dSpace.mlkitImagePixels);
  });

  test('upright geometry handles rotation without applying it twice', () {
    expect(uprightCameraPoint(100, 60, 640, 480, 90, alreadyRotated: false),
        (1 - 60 / 480, 100 / 640));
    expect(uprightCameraPoint(420, 100, 640, 480, 90, alreadyRotated: true),
        (420 / 480, 100 / 640));
    expect(uprightCameraPoint(100, 60, 640, 480, 270, alreadyRotated: false),
        (60 / 480, 1 - 100 / 640));
    expect(uprightCameraPoint(100, 60, 640, 480, 0, alreadyRotated: false),
        (100 / 640, 60 / 480));
  });

  test('loader requests only reference JSON and rejects missing/old references',
      () async {
    final repository =
        PrayerReferenceRepository(client: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/prayer-reference');
      return http.Response.bytes(
          utf8.encode(jsonEncode(referenceFixture())), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final reference = await repository.load('http://localhost:8000');
    expect(reference.segments.length, 6);
    repository.close();
    expect(
        () => PrayerReference.fromJson(
            {...referenceFixture(), 'schema_version': 1}),
        throwsFormatException);
    final missing = PrayerReferenceRepository(
        client: MockClient((_) async => http.Response('{}', 404)));
    await expectLater(
        missing.load('http://localhost:8000'), throwsFormatException);
    await expectLater(
        missing.load('file:///etc/config'), throwsFormatException);
    missing.close();
  });
}
