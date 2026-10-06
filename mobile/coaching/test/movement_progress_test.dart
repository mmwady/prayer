import 'package:coaching/accounts/movement_progress.dart';
import 'package:coaching/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy summaries keep missing coverage explicit', () {
    expect(MovementProgress.summary({}), contains('غير متاحة'));
    expect(MovementProgress.summary({'movement_score': null}),
        contains('القديمة'));
    expect(
        MovementProgress.summary({
          'weekly_movement_score': 75,
          'weekly_movements_detected': 12,
          'weekly_movements_expected': 16,
        }, weekly: true),
        '75.0٪ • 12/16 حركة');
  });

  testWidgets('coverage and review remain separate in a narrow account view',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = {
      'date': '2026-10-06',
      'movement_score': 75.0,
      'movements_detected': 12,
      'movements_expected': 16,
      'movement_results': {
        'fajr': {
          'movement_score': 75.0,
          'movements_detected': 12,
          'movements_expected': 16,
          'uncertain': true,
        }
      },
    };
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(children: [
            MovementProgress(progress: {
              ...day,
              'weekly_movement_score': 75.0,
              'weekly_movements_detected': 12,
              'weekly_movements_expected': 16,
              'week': [day],
            })
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('اكتمال الحركات المرصودة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-10-06'));
    await tester.pumpAndSettle();
    expect(find.text('تحتاج مراجعة'), findsOneWidget);
    expect(find.text('الفجر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
