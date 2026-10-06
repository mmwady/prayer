import 'dart:convert';
import 'dart:io';

import 'package:coaching/l10n/app_localizations.dart';
import 'package:coaching/l10n/english_strings.dart';
import 'package:coaching/main.dart';
import 'package:coaching/mosque/client.dart';
import 'package:coaching/mosque/screen.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/screens/video_analysis_screen.dart';
import 'package:coaching/screens/prayer_illustrations_screen.dart';
import 'package:coaching/screens/prayer_training_screen.dart';
import 'package:coaching/state/locale_provider.dart';
import 'package:coaching/ui/app_theme.dart';
import 'package:coaching/video/analysis_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'video_analysis_test.dart' as fixtures;

const delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Arabic default, English persistence and unsupported locale rejection',
      () async {
    final state = LocaleProvider();
    await state.load();
    expect(state.localeCode, 'ar');
    expect(state.isRtl, isTrue);
    await state.setLocale('en');
    expect(state.isRtl, isFalse);
    final restored = LocaleProvider();
    await restored.load();
    expect(restored.localeCode, 'en');
    await restored.setLocale('fr');
    expect(restored.localeCode, 'en');
    await restored.setLocale('ar');
    final arabic = LocaleProvider();
    await arabic.load();
    expect(arabic.localeCode, 'ar');
  });

  test('catalog placeholders match and arbitrary data is preserved', () {
    final placeholders = RegExp(r'\{\d+\}');
    for (final entry in englishStrings.entries) {
      expect(
          placeholders.allMatches(entry.value).map((m) => m[0]).toList()
            ..sort(),
          placeholders.allMatches(entry.key).map((m) => m[0]).toList()..sort(),
          reason: entry.key);
    }
    const english = AppLocalizations(Locale('en'));
    const arabic = AppLocalizations(Locale('ar'));
    expect(english.text('السلام عليكم يا {0}', ['القيام']),
        'Assalamu alaykum, القيام');
    expect(english.text('تعذر فتح التقرير: disk full'),
        'Could not open report: disk full');
    expect(english.text('ملف شخصي خاص.mp4'), 'ملف شخصي خاص.mp4');
    expect(english.text('REVIEW_REQUIRED'), 'REVIEW_REQUIRED');
    expect(arabic.text('الركعة {0} من {1}', [1, 2]), 'الركعة 1 من 2');
  });

  testWidgets('language menu switches direction and retains prayer navigation',
      (tester) async {
    final locale = LocaleProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: locale, child: const CoachingApp()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('صلاة الفجر'), 250);
    expect(find.text('صلاة الفجر'), findsOneWidget);
    await tester.tap(find.byTooltip('اللغة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Fajr prayer'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('Fajr prayer'))),
        TextDirection.ltr);
    await tester.ensureVisible(find.text('Fajr prayer'));
    await tester.tap(find.text('Fajr prayer'));
    await tester.pumpAndSettle();
    expect(find.text('Video analysis — Fajr prayer'), findsOneWidget);
    final screenState = tester.state(find.byType(VideoAnalysisScreen));
    await locale.setLocale('ar');
    await tester.pumpAndSettle();
    expect(find.text('تحليل فيديو — صلاة الفجر'), findsOneWidget);
    expect(tester.state(find.byType(VideoAnalysisScreen)), same(screenState));
    expect(
        Directionality.of(
            tester.element(find.text('تحليل فيديو — صلاة الفجر'))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Arabic and English reports render at phone and desktop widths without mutating results',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [320.0, 390.0, 820.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final code in ['ar', 'en']) {
        final raw = fixtures.fixture(complete: false);
        final original = jsonEncode(raw);
        final report = AnalysisReport.fromJson(raw);
        await tester.pumpWidget(MaterialApp(
            locale: Locale(code),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: delegates,
            theme: buildAppTheme(),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: AnalysisResults(
                        report: report, api: fixtures.fakeApi([]))))));
        await tester.pumpAndSettle();
        expect(
            find.text(code == 'en' ? 'Rakah 1' : 'الركعة 1'), findsOneWidget);
        expect(
            find.text(code == 'en'
                ? 'Ruku — Review needed'
                : 'الركوع — تحتاج مراجعة'),
            findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$code at $width');
        expect(jsonEncode(raw), original);
        expect(report.overallResult, 'REVIEW_REQUIRED');
        expect(report.rakahs.first.stations.first.status, 'UNCONFIRMED');
        if (code == 'en') {
          final visibleArabic = tester
              .widgetList<Text>(find.byType(Text))
              .where((text) =>
                  RegExp(r'[\u0600-\u06ff]').hasMatch(text.data ?? ''));
          expect(visibleArabic.map((text) => text.data).toList(), isEmpty);
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets(
      'English teaching labels, synthetic training and mosque direction',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget english(Widget child) => MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: delegates,
        theme: buildAppTheme(),
        home: child);
    await tester.pumpWidget(english(const PrayerIllustrationsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('1. Opening Takbir'), findsOneWidget);
    expect(find.bySemanticsLabel('Opening Takbir'), findsWidgets);
    expect(tester.takeException(), isNull);

    var now = DateTime(2026);
    await tester.pumpWidget(english(PrayerTrainingScreen(
        definition: PrayerCatalog.of(PrayerType.demo), clock: () => now)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Demo simulation — no camera'), 100);
    await tester.tap(find.text('Demo simulation — no camera'));
    await tester.pump();
    for (var i = 0; i < 100; i++) {
      now = now.add(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Training completed'), findsOneWidget);
    expect(find.text('Observed movements: 6 / 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());

    final fixture = jsonDecode(
        File('test/fixtures/mosque_companion.json').readAsStringSync()) as Map;
    final client = CompanionClient()
      ..state = Map<String, dynamic>.from(fixture['confirmed'])
      ..token = 'fixture'
      ..enabled = true;
    await tester.pumpWidget(english(MosqueCompanionScreen(client: client)));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.text('Mosque Companion'))),
        TextDirection.ltr);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
}
