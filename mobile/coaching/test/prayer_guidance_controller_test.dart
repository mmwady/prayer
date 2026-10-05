import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coaching/models/keypoint.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/prayer/prayer_demo_detector.dart';
import 'package:coaching/prayer/prayer_sequence_engine.dart';
import 'package:coaching/services/pose_detector.dart';
import 'package:coaching/services/prayer_guidance_client.dart';
import 'package:coaching/state/prayer_controller.dart';

class TestDetector extends PoseDetector {
  final frames = StreamController<List<Keypoint>>.broadcast(sync: true);
  @override
  Stream<List<Keypoint>> get stream => frames.stream;
  @override
  Widget buildPreview() => const SizedBox();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await frames.close();
  }
}

class FakeGuidanceSource implements PrayerGuidanceSource {
  FakeGuidanceSource({this.reply = 'ثبّت الوضعية قليلًا', this.fail = false});

  final String reply;
  final bool fail;
  final List<PrayerGuidanceRequest> requests = [];

  @override
  Future<PrayerGuidance?> request(PrayerGuidanceRequest request) async {
    requests.add(request);
    if (fail) throw StateError('offline');
    return PrayerGuidance(text: reply, model: 'deepseek-flash', degraded: false);
  }

  @override
  void close() {}
}

void main() {
  late DateTime now;
  late TestDetector detector;

  setUp(() {
    now = DateTime(2026);
    detector = TestDetector();
  });

  PrayerController controller(PrayerGuidanceSource? guidance) =>
      PrayerController(
        definition: PrayerCatalog.of(PrayerType.demo),
        detector: detector,
        guidance: guidance,
        clock: () => now,
      );

  void frame(PrayerPose pose) {
    now = now.add(const Duration(milliseconds: 200));
    detector.frames.add(syntheticPrayerKeypoints(pose));
  }

  void station(PrayerPose pose) {
    for (var i = 0; i < 4; i++) {
      frame(pose);
    }
  }

  Future<void> settle(PrayerController c) async {
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    await Future<void>.delayed(Duration.zero);
  }

  test('no guidance source means no requests and unchanged progression',
      () async {
    final c = controller(null);
    await c.start();

    station(PrayerPose.standing);
    await Future<void>.delayed(Duration.zero);

    expect(c.guidanceText, isNull);
    expect(c.state.completedStations, isNotEmpty);
    await settle(c);
  });

  test('a successful station advance alone does not request guidance', () async {
    final source = FakeGuidanceSource();
    final c = controller(source);
    await c.start();

    // Expected station 1 is `standing`; matching it advances without a cue.
    station(PrayerPose.standing);
    await Future<void>.delayed(Duration.zero);

    expect(c.state.completedStations, isNotEmpty);
    expect(source.requests, isEmpty);
    expect(c.guidanceText, isNull);
    await settle(c);
  });

  test('a retry episode requests guidance exactly once and exposes the text',
      () async {
    final source = FakeGuidanceSource();
    final c = controller(source);
    await c.start();

    // Expected station is `standing`, so `ruku` is a skip/unexpected episode.
    // Many frames must still produce a single cue.
    for (var i = 0; i < 10; i++) {
      frame(PrayerPose.ruku);
    }
    await Future<void>.delayed(Duration.zero);

    expect(c.state.retryCount, greaterThan(0));
    expect(source.requests.length, 1);
    final request = source.requests.single;
    expect(request.event, 'retry');
    // The cue describes the station the learner should be in — the expected one.
    expect(request.station, 'standing');
    expect(request.prayer, 'demo');
    expect(request.rakah, 1);
    expect(c.guidanceText, 'ثبّت الوضعية قليلًا');
    expect(c.guidanceDegraded, isFalse);
    expect(c.guidancePending, isFalse);
    await settle(c);
  });

  test('completing every station requests the completion cue', () async {
    final source = FakeGuidanceSource(reply: 'أتممت الحركات المطلوبة.');
    final c = controller(source);
    await c.start();

    station(PrayerPose.standing);
    station(PrayerPose.ruku);
    station(PrayerPose.standing);
    station(PrayerPose.sujood);
    station(PrayerPose.sitting);
    station(PrayerPose.sujood);
    await Future<void>.delayed(Duration.zero);

    expect(c.state.sessionStatus, SessionStatus.completed);
    expect(source.requests.map((r) => r.event), contains('completed'));
    expect(c.guidanceText, 'أتممت الحركات المطلوبة.');
    await settle(c);
  });

  test('a failing guidance source never blocks the session', () async {
    final source = FakeGuidanceSource(fail: true);
    final c = controller(source);
    await c.start();

    // Advance legitimately, then skip ahead to force a retry episode.
    station(PrayerPose.standing);
    station(PrayerPose.sujood);
    await Future<void>.delayed(Duration.zero);

    expect(source.requests, isNotEmpty);
    expect(c.guidanceText, isNull);
    expect(c.guidancePending, isFalse);
    expect(c.guidanceError, isNotNull);
    // Progression is unaffected by the failed advisory call.
    expect(c.state.completedStations, isNotEmpty);
    expect(c.state.retryCount, greaterThan(0));
    await settle(c);
  });
}
