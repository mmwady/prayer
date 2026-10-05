import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coaching/screens/video_analysis_screen.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/ui/app_theme.dart';
import 'package:coaching/video/analysis_controller.dart';
import 'package:coaching/video/analysis_report.dart';
import 'video_analysis_test.dart' as fixtures;

// These fixtures are only visual QA, never part of the application runtime.
class ProcessingFixture extends AnalysisController {
  ProcessingFixture()
      : super(source: fixtures.FakeVideo(), api: fixtures.fakeApi([])) {
    phase = AnalysisPhase.processing;
    total = 120;
    prepared = uploaded = 120;
    processed = 64;
  }
  @override
  bool get busy => true;
}

void main() {
  testWidgets('mobile processing and uncertain report render without overflow',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final loader = FontLoader('IqtadiArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await tester.runAsync(loader.load);
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(icons.load);
    for (final width in [320.0, 390.0, 820.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final report in [false, true]) {
        final c = report
            ? AnalysisController(
                source: fixtures.FakeVideo(), api: fixtures.fakeApi([]))
            : ProcessingFixture();
        if (report) {
          c.report = AnalysisReport.fromJson(fixtures.fixture(complete: false));
        }
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(),
            home: Directionality(
                textDirection: TextDirection.rtl,
                child: RepaintBoundary(
                    key: key,
                    child: VideoAnalysisScreen(
                        definition: PrayerCatalog.of(PrayerType.fajr),
                        controller: c)))));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        if (width == 390) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image =
              (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
          final data = await tester
              .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
          await tester.runAsync(() async {
            final file = File(
                '../../output/redesign/${report ? 'report-qa' : 'processing-qa'}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
          });
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    }
  });
}
