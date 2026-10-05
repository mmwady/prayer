import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coaching/mosque/client.dart';
import 'package:coaching/mosque/screen.dart';
import 'package:coaching/ui/app_theme.dart';

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/mosque_companion.json').readAsStringSync())
          as Map;
  testWidgets(
      'Arabic phone flow: origin, denied GPS, mosque, details and candidates',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final font = FontLoader('IqtadiArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await tester.runAsync(font.load);
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(icons.load);
    for (final width in [320.0, 390.0, 820.0]) {
      tester.view.physicalSize = Size(width, 844);
      final client = CompanionClient(transport: MockClient((request) async {
        dynamic response = {};
        if (request.url.path.endsWith('/preview')) {
          response = {'places': fixture['preview']};
        }
        if (request.url.path.endsWith('/requests')) {
          response = {'id': fixture['id'], 'state': fixture['created']};
        }
        if (request.url.path.endsWith('/matches')) {
          response = {'matches': fixture['matches']};
        }
        if (request.url.path.endsWith('/actions')) {
          response = fixture['searching'];
        }
        return http.Response.bytes(utf8.encode(jsonEncode(response)), 200);
      }))
        ..state = Map<String, dynamic>.from(fixture['initial'])
        ..token = 'fixture'
        ..enabled = true;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: RepaintBoundary(
              key: key, child: MosqueCompanionScreen(client: client))));
      await tester.pumpAndSettle();
      Future<void> tap(String label) async {
        final finder = find.text(label);
        for (var attempt = 0;
            finder.hitTestable().evaluate().isEmpty && attempt < 30;
            attempt++) {
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        expect(finder.hitTestable(), findsWidgets);
        await tester.tap(finder.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> shot(String name) async {
        if (width != 390) {
          return;
        }
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image =
            (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
        final data = await tester
            .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
        await tester.runAsync(() async {
          final file = File('../../output/mosque/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
        });
        image.dispose();
      }

      await shot('home');
      await tap('أحتاج رفيقًا');
      await shot('origin');
      if (width == 390) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('iqtadi/mosque_location'), (call) async {
          throw PlatformException(code: 'DENIED');
        });
        await tap('موقعي الحالي — اطلب إذن GPS');
        await tap('أوافق');
        expect(find.textContaining('تعذر GPS أو رُفض الإذن'), findsOneWidget);
        expect(client.state!['me']['home'], isNull);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('iqtadi/mosque_location'),
                (call) async =>
                    {'lat': 24.444, 'lng': 39.617, 'accuracy': 150.0});
        await tap('موقعي الحالي — اطلب إذن GPS');
        await tap('أوافق');
        expect(find.textContaining('دقة ضعيفة'), findsOneWidget);
        expect(client.state!['me']['home'], isNull);
      }
      await tap('التالي: اختيار المسجد');
      expect(client.error, isNull);
      expect(find.text('اختر المسجد'), findsOneWidget);
      await shot('mosques');
      await tester.scrollUntilVisible(find.text('مسجد قباء'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('مسجد قباء'), findsOneWidget);
      await tap('التالي: تفاصيل الرحلة');
      await shot('details');
      await tap('اعرض الرفقاء المناسبين');
      await tester.scrollUntilVisible(find.text('يوسف'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('يوسف'), findsOneWidget);
      expect(find.textContaining('انحراف محاكى'), findsWidgets);
      await shot('matches');
      await tap('طلب الانضمام');
      await tester.scrollUntilVisible(
          find.textContaining('بانتظار المرافق'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('بانتظار المرافق'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    }
  });
  testWidgets('Confirmed walking trip renders meeting on small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = CompanionClient()
      ..state = Map<String, dynamic>.from(fixture['confirmed'])
      ..token = 'fixture';
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(), home: MosqueCompanionScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('رحلتي'));
    await tester.tap(find.text('رحلتي'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تم تأكيد الطرفين'), findsOneWidget);
    expect(find.text('خرجت'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
  test('failed persona switch retains the authorized view', () async {
    final client = CompanionClient(
        transport: MockClient((request) async => http.Response.bytes(
            utf8.encode(jsonEncode({'detail': 'الخادم غير متاح'})), 503)))
      ..actor = 'U01'
      ..state = Map<String, dynamic>.from(fixture['initial'])
      ..token = 'fixture';
    await client.switchActor('U05');
    expect(client.actor, 'U01');
    expect(client.state!['me']['id'], 'U01');
    expect(client.error, isNotNull);
    client.dispose();
  });
  testWidgets(
      'elder arrival retains return obligation and renders without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('IqtadiArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await tester.runAsync(font.load);
    final client = CompanionClient()
      ..actor = 'U04'
      ..state = Map<String, dynamic>.from(fixture['elder_arrived'])
      ..token = 'fixture';
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: RepaintBoundary(
            key: key, child: MosqueCompanionScreen(client: client))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('رحلتي'));
    await tester.tap(find.text('رحلتي'));
    await tester.pumpAndSettle();
    expect(find.textContaining('العودة ما زالت ملتزمًا بها'), findsOneWidget);
    expect(find.text('بدأنا العودة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final image = (await tester.runAsync(() =>
        (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1)))!;
    final bytes = await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
    await tester.runAsync(() => File('../../output/mosque/elder-arrived.png')
        .writeAsBytes(bytes!.buffer.asUint8List()));
    image.dispose();
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
}
