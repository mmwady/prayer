import 'package:flutter_test/flutter_test.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/prayer/prayer_sequence_engine.dart';

void main() {
  late DateTime now;
  setUp(() => now = DateTime(2026));
  void hold(PrayerSequenceEngine e, PrayerPose pose,
      {double confidence = 0.95}) {
    for (var i = 0; i < 7; i++) {
      now = now.add(const Duration(milliseconds: 100));
      e.observe(PoseObservation(pose, confidence), now);
    }
  }

  PrayerSequenceEngine demo() =>
      PrayerSequenceEngine(PrayerCatalog.of(PrayerType.demo));

  test('central prayer counts and configured sittings', () {
    const counts = {
      PrayerType.fajr: 2,
      PrayerType.dhuhr: 4,
      PrayerType.asr: 4,
      PrayerType.maghrib: 3,
      PrayerType.isha: 4,
      PrayerType.demo: 1
    };
    for (final entry in counts.entries) {
      final p = PrayerCatalog.of(entry.key);
      expect(p.rakahCount, entry.value);
      expect(p.rakahs.last.hasFinalSitting, entry.key != PrayerType.demo);
      expect(p.rakahs.where((r) => r.hasIntermediateSitting).length,
          entry.value > 2 ? 1 : 0);
    }
    expect(PrayerCatalog.of(PrayerType.demo).stationCount, 6);
    expect(PrayerCatalog.of(PrayerType.dhuhr).stationCount, 26);
  });

  test('single frame or confidence/unknown/NaN cannot advance', () {
    final e = demo();
    e.observe(const PoseObservation(PrayerPose.standing, 0.95), now);
    expect(e.state.completedStations, isEmpty);
    hold(e, PrayerPose.standing, confidence: 0.2);
    hold(e, PrayerPose.unknown);
    hold(e, PrayerPose.standing, confidence: double.nan);
    expect(e.state.completedStations, isEmpty);
    expect(e.state.lowConfidenceEvents, 1);
    hold(e, PrayerPose.standing);
    expect(e.state.completedStations.length, 1);
    hold(e, PrayerPose.ruku, confidence: 0.3);
    expect(e.state.lowConfidenceEvents, 2);
  });

  test('six demo stations complete, held poses count once', () {
    final e = demo();
    for (final station in e.definition.rakahs.single.stations) {
      hold(e, station.pose);
      final count = e.state.completedStations.length;
      hold(e, station.pose);
      expect(e.state.completedStations.length, count);
    }
    expect(e.state.coreMovements, 6);
    expect(e.state.completedRakahs, 1);
    expect(e.state.sessionStatus, SessionStatus.completed);
    expect(e.state.expectedStation, isNull);
  });

  test('skipped standing after ruku does not advance and can recover', () {
    final e = demo();
    hold(e, PrayerPose.standing);
    hold(e, PrayerPose.ruku);
    hold(e, PrayerPose.sujood);
    hold(e, PrayerPose.sujood);
    expect(e.state.expectedStation, PrayerStation.standingAfterRuku);
    expect(e.state.feedback, MovementFeedback.skipped);
    expect(e.state.retryCount, 1);
    hold(e, PrayerPose.standing);
    expect(e.state.expectedStation, PrayerStation.sujood1);
  });

  test('obvious returned previous pose records repetition', () {
    final e = demo();
    hold(e, PrayerPose.standing);
    hold(e, PrayerPose.ruku);
    hold(e, PrayerPose.standing);
    hold(e, PrayerPose.ruku);
    expect(e.state.expectedStation, PrayerStation.sujood1);
    expect(e.state.feedback, MovementFeedback.repeated);
    expect(e.state.retryCount, 1);
  });

  test('gaps and out-of-order frames do not establish persistence', () {
    final e = demo();
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(seconds: 1));
      e.observe(const PoseObservation(PrayerPose.standing, 0.9), now);
    }
    e.observe(const PoseObservation(PrayerPose.standing, 0.9),
        now.subtract(const Duration(seconds: 1)));
    expect(e.state.completedStations, isEmpty);
    hold(e, PrayerPose.standing);
    expect(e.state.completedStations.length, 1);
  });

  test('incorrect stable pose and stopped session cannot advance', () {
    final e = demo();
    hold(e, PrayerPose.sitting);
    expect(e.state.completedStations, isEmpty);
    expect(e.state.retryCount, 1);
    e.stop();
    hold(e, PrayerPose.standing);
    expect(e.state.sessionStatus, SessionStatus.stopped);
    expect(e.state.completedStations, isEmpty);
  });

  for (final type in PrayerType.values) {
    test(
        '${type.name} uses one engine and completes only after configured sittings',
        () {
      final e = PrayerSequenceEngine(PrayerCatalog.of(type));
      for (final r in e.definition.rakahs) {
        for (final station in r.stations) {
          expect(e.state.expectedStation, station);
          hold(e, station.pose);
        }
        expect(e.state.completedRakahs, r.index);
      }
      expect(e.state.sessionStatus, SessionStatus.completed);
      expect(e.state.coreMovements, e.definition.rakahCount * 6);
      expect(e.state.completedStations.length, e.definition.stationCount);
      expect(e.state.retryCount, 0);
    });
  }
}
