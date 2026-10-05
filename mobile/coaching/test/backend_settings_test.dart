import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:coaching/config/env.dart';
import 'package:coaching/ui/app_theme.dart';
import 'package:coaching/ui/backend_settings_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings renders on narrow mobile with large text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final font = FontLoader('IqtadiArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await tester.runAsync(font.load);
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(icons.load);
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                  data: MediaQueryData(
                      size: Size(width, 844),
                      textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
                  child: RepaintBoundary(
                      key: key,
                      child: const Scaffold(body: BackendSettingsDrawer()))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width == 390) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image =
            (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
        final data = await tester
            .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
        await tester.runAsync(() async {
          final file = File('../../output/backend-settings-qa.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
        });
        image.dispose();
      }
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Env.reset();
  });
  test('URL validation accepts root HTTP(S) and rejects API paths and secrets',
      () {
    expect(Env.normalizeUrl(' https://test.trycloudflare.com/ '),
        'https://test.trycloudflare.com');
    expect(Env.normalizeUrl('http://10.0.2.2:8000'), 'http://10.0.2.2:8000');
    for (final value in [
      '',
      'ftp://host',
      'https://host/api',
      'https://user:pass@host',
      'https://host?token=x',
      'https://host#x'
    ]) {
      expect(() => Env.normalizeUrl(value), throwsFormatException);
    }
  });
  test('saved address survives load and reset restores build default',
      () async {
    await Env.save('https://test.trycloudflare.com/');
    await Env.load();
    expect(Env.backendUrl, 'https://test.trycloudflare.com');
    expect((await SharedPreferences.getInstance()).getString('backend_url'),
        Env.backendUrl);
    await Env.reset();
    expect(Env.backendUrl, Env.defaultBackendUrl);
  });
  testWidgets('drawer validates, saves and restores backend address',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: BackendSettingsDrawer()))));
    await tester.enterText(find.byType(TextFormField), 'bad');
    await tester.tap(find.text('حفظ الرابط'));
    await tester.pumpAndSettle();
    expect(Env.backendUrl, Env.defaultBackendUrl);
    await tester.enterText(
        find.byType(TextFormField), 'https://test.trycloudflare.com');
    await tester.tap(find.text('حفظ الرابط'));
    await tester.pumpAndSettle();
    expect(Env.backendUrl, 'https://test.trycloudflare.com');
    await tester.tap(find.text('استعادة الرابط الافتراضي'));
    await tester.pumpAndSettle();
    expect(Env.backendUrl, Env.defaultBackendUrl);
  });
}
