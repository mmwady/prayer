import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:coaching/main.dart';
import 'package:coaching/state/locale_provider.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/screens/prayer_training_screen.dart';

void main() {
  testWidgets('Arabic prayer picker opens recorded video selection',
      (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LocaleProvider(), child: const CoachingApp()));
    expect(find.text('اقتدِ'), findsOneWidget);
    expect(find.text('صلاة الفجر'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('اقتدِ'))),
        TextDirection.rtl);
    await tester.scrollUntilVisible(find.text('ركعة تجريبية'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ركعة تجريبية'));
    await tester.pumpAndSettle();
    expect(find.text('اختيار فيديو محلي'), findsOneWidget);
  });

  testWidgets('synthetic demo runs detector to classifier to engine to summary',
      (tester) async {
    var now = DateTime(2026);
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: PrayerTrainingScreen(
                definition: PrayerCatalog.of(PrayerType.demo),
                clock: () => now))));
    await tester.tap(find.text('محاكاة للتجربة — دون كاميرا'));
    await tester.pump();
    for (var i = 0; i < 100; i++) {
      now = now.add(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('تم إكمال التدريب'), findsOneWidget);
    expect(find.text('الحركات المرصودة: 6 / 6'), findsOneWidget);
    expect(find.text('ملخص محاكاة — ليس رصداً لحركاتك'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
