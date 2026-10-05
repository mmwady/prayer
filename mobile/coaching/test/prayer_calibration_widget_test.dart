import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coaching/models/keypoint.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/screens/prayer_training_screen.dart';
import 'package:coaching/services/pose_detector.dart';
import 'package:coaching/services/prayer_guidance_client.dart';
import 'package:coaching/state/prayer_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/prayer_reference_fixture.dart';

class CalibrationTestDetector extends PoseDetector
    implements PosePreviewGeometry {
  final frames = StreamController<List<Keypoint>>.broadcast(sync: true);
  @override
  Stream<List<Keypoint>> get stream => frames.stream;
  @override
  double get previewAspectRatio => 1;
  @override
  bool get previewMirrored => true;
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await frames.close();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'calibration locks start, overlays preview, revokes readiness and never counts frames',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final detector = CalibrationTestDetector();
    var now = DateTime(2026);
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: PrayerTrainingScreen(
                definition: PrayerCatalog.of(PrayerType.demo),
                initialReference: calibrationReference(),
                detectorFactory: () => detector,
                clock: () => now))));
    await tester.ensureVisible(find.text('افتح الكاميرا واضبط التصوير'));
    await tester.tap(find.text('افتح الكاميرا واضبط التصوير'));
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'ابدأ التدريب');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    final c = tester
        .element(find.text('ضبط التصوير قبل الصلاة'))
        .read<PrayerController>();
    for (var i = 0; i < 16; i++) {
      now = now.add(const Duration(milliseconds: 100));
      detector.frames.add(calibrationPoints());
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(c.state.completedStations, isEmpty);
    now = now.add(const Duration(milliseconds: 100));
    detector.frames.add([]);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    for (var i = 0; i < 16; i++) {
      now = now.add(const Duration(milliseconds: 100));
      detector.frames.add(calibrationPoints());
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.canBegin, isTrue);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    for (var i = 0; i < 16; i++) {
      now = now.add(const Duration(milliseconds: 100));
      detector.frames.add(calibrationPoints());
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(c.sessionBegun, isTrue);
    expect(c.state.completedStations, isEmpty);
    expect(find.text('ضبط التصوير قبل الصلاة'), findsNothing);
    for (var i = 0; i < 7; i++) {
      now = now.add(const Duration(milliseconds: 100));
      detector.frames.add(calibrationPoints());
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c.state.completedStations.length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'local training is available without a server or active reference',
      (tester) async {
    final detector = CalibrationTestDetector();
    await tester.pumpWidget(MaterialApp(
        home: PrayerTrainingScreen(
            definition: PrayerCatalog.of(PrayerType.demo),
            detectorFactory: () => detector)));
    await tester.pumpAndSettle();
    final button =
        find.widgetWithText(FilledButton, 'افتح الكاميرا للتدريب المحلي');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(find.text('المراجع والإرشادات المحلية'), findsOneWidget);
    expect(find.text('عنوان backend'), findsNothing);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('تدريب هندسي محلي'), findsOneWidget);
    final controller =
        tester.element(find.text('تدريب هندسي محلي')).read<PrayerController>();
    expect(controller.reference, isNull);
    expect(controller.calibrating, isFalse);
    expect(controller.guidance, isA<LocalPrayerGuidanceSource>());
    detector.frames.add([]);
    await tester.pump();
    expect(controller.state.completedStations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
