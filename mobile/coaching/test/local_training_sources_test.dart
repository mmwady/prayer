import 'dart:convert';

import 'package:coaching/prayer/local_prayer_reference_repository.dart';
import 'package:coaching/prayer/prayer_content.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/services/prayer_guidance_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coaching/screens/local_prayer_references_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/prayer_reference_fixture.dart';

PrayerGuidanceRequest cue(String event, PrayerStation station) =>
    PrayerGuidanceRequest(
        prayer: 'demo',
        station: wireStation(station),
        event: event,
        rakah: 1,
        stationIndex: 0,
        totalStations: 6,
        retries: 0,
        coreMovementsDone: 0);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('local guidance covers discrete events and uses bundled content',
      () async {
    const source = LocalPrayerGuidanceSource();
    for (final station in PrayerStation.values) {
      for (final event in [
        'start',
        'retry',
        'uncertain',
        'completed',
        'stopped'
      ]) {
        final response = await source.request(cue(event, station));
        expect(response!.text, isNotEmpty);
        expect(response.model, 'local:${PrayerContent.version}');
        expect(response.degraded, isFalse);
        expect(response.text, isNot(contains('صلاة صحيحة')));
      }
    }
    expect(await source.request(cue('frame', PrayerStation.standing)), isNull);
  });

  test('no bundled calibration reference is fabricated', () async {
    final repository = LocalPrayerReferenceRepository();
    expect(await repository.load(), isNull);
  });

  test('reviewed import persists locally and preserves all authoring metadata',
      () async {
    final repository = LocalPrayerReferenceRepository();
    final input = referenceFixture()
      ..['authoring_notes'] = {
        'note': 'Measured fixture only',
        'excluded_frames': [7]
      };
    final source = jsonEncode(input);
    final reference = await repository.save(source, reviewConfirmed: true);
    input['name'] = 'Mutated caller data';
    expect(reference.name, 'مرجع اختبار اصطناعي');
    final reloaded = await repository.load();
    expect(reloaded!.segments.length, 6);
    expect(jsonDecode(repository.export(reloaded)), jsonDecode(source));
    await repository.clear();
    expect(await repository.load(), isNull);
  });

  test(
      'unreviewed, incomplete, old and oversized imports never replace active reference',
      () async {
    final repository = LocalPrayerReferenceRepository();
    final original = jsonEncode(referenceFixture());
    await repository.save(original, reviewConfirmed: true);
    await expectLater(repository.save(original, reviewConfirmed: false),
        throwsFormatException);
    expect(
        () => repository
            .parse(jsonEncode({...referenceFixture(), 'segments': []})),
        throwsFormatException);
    expect(
        () => repository
            .parse(jsonEncode({...referenceFixture(), 'schema_version': 1})),
        throwsFormatException);
    expect(() => repository.parse(jsonEncode({'id': 'incomplete'})),
        throwsFormatException);
    expect(
        () => repository
            .parse('x' * (LocalPrayerReferenceRepository.maximumBytes + 1)),
        throwsFormatException);
    expect((await repository.load())!.name, 'مرجع اختبار اصطناعي');
  });

  test('cache schema or review changes invalidate the saved reference',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = LocalPrayerReferenceRepository();
    for (final wrapper in [
      {
        'local_schema_version': 0,
        'review_confirmed': true,
        'reference': referenceFixture()
      },
      {
        'local_schema_version': 1,
        'review_confirmed': false,
        'reference': referenceFixture()
      },
      {
        'local_schema_version': 1,
        'review_confirmed': true,
        'reference': {'schema_version': 1}
      },
    ]) {
      await preferences.setString(
          LocalPrayerReferenceRepository.storageKey, jsonEncode(wrapper));
      try {
        expect(await repository.load(), isNull);
      } on FormatException {
        // Corrupt evidence is explicitly reported after invalidation.
      }
      expect(preferences.containsKey(LocalPrayerReferenceRepository.storageKey),
          isFalse);
    }
  });

  testWidgets(
      'reference editor needs explicit review and offers local export/delete',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(const MaterialApp(home: LocalPrayerReferencesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('المرجع المحلي المفعّل'), findsNothing);
    final save = find.widgetWithText(FilledButton, 'حفظ وتفعيل محليًا');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('local-reference-json')),
        jsonEncode(referenceFixture()));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await LocalPrayerReferenceRepository().load())!.segments.length, 6);
    await tester.drag(find.byType(ListView), const Offset(0, 1400));
    await tester.pumpAndSettle();
    expect(find.text('المرجع المحلي المفعّل'), findsOneWidget);
    expect(find.text('تصدير JSON'), findsOneWidget);
    final remove = find.text('حذف المرجع المحلي');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 1400));
    await tester.pumpAndSettle();
    expect(find.text('المرجع المحلي المفعّل'), findsNothing);
    expect(await LocalPrayerReferenceRepository().load(), isNull);
    expect(tester.takeException(), isNull);
  });
}
