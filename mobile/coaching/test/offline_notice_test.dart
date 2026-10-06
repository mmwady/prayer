import 'dart:async';

import 'package:coaching/local/offline_notice.dart';
import 'package:coaching/local/offline_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page(OfflineNotice notice) => MaterialApp(home: Scaffold(body: notice));

void main() {
  test('offline progress bounds malformed and missing counters', () {
    expect(const OfflineStatus(state: 'preparing').progress, isNull);
    expect(
        OfflineStatus.fromJson(
            {'state': 'preparing', 'completed': 15, 'total': 10}).progress,
        1);
    expect(OfflineStatus.fromJson({'completed': double.nan, 'total': -1}).total,
        0);
  });

  testWidgets('native notice is absent and does not read browser status',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(_page(OfflineNotice(readStatus: () async {
      reads++;
      return const OfflineStatus(state: 'installed', ready: true);
    })));
    await tester.pump(const Duration(seconds: 4));
    expect(reads, 0);
    expect(find.text('صورك وفيديوهاتك تبقى على جهازك.'), findsNothing);
  });

  testWidgets(
      'shows preparation progress, polls at two seconds and cancels on dispose',
      (tester) async {
    var reads = 0;
    var status =
        const OfflineStatus(state: 'preparing', completed: 3, total: 10);
    await tester.pumpWidget(_page(OfflineNotice(
        enabled: true,
        readStatus: () async {
          reads++;
          return status;
        })));
    await tester.pump();
    expect(reads, 1);
    expect(find.text('جارٍ تجهيز التدريب دون إنترنت'), findsOneWidget);
    expect(find.text('حُفظ 3 من 10 ملفًا'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .3);
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 1);
    status = const OfflineStatus(
        state: 'ready', ready: true, completed: 10, total: 10);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(reads, 2);
    expect(find.text('جاهز للتدريب دون اتصال'), findsOneWidget);
    expect(find.text('تطبيق التحديث'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
    expect(reads, 2);
  });

  testWidgets('status reads never overlap while a previous read is pending',
      (tester) async {
    final pending = Completer<OfflineStatus>();
    var reads = 0;
    await tester.pumpWidget(_page(OfflineNotice(
        enabled: true,
        readStatus: () {
          reads++;
          return pending.future;
        })));
    await tester.pump(const Duration(seconds: 6));
    expect(reads, 1);
    pending.complete(const OfflineStatus(state: 'ready', ready: true));
    await tester.pump();
    expect(find.text('جاهز للتدريب دون اتصال'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('updates require a visible explicit tap, never polling',
      (tester) async {
    var updates = 0;
    await tester.pumpWidget(_page(OfflineNotice(
      enabled: true,
      readStatus: () async =>
          const OfflineStatus(state: 'update_available', ready: true),
      applyUpdate: () async {
        updates++;
        return false;
      },
    )));
    await tester.pump();
    expect(find.text('تحديث التطبيق جاهز'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(updates, 0);
    await tester.tap(find.text('تطبيق التحديث'));
    await tester.pump();
    expect(updates, 1);
    expect(find.text('لم يبدأ التحديث؛ أعد المحاولة بعد اكتمال حفظ الملفات.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'failed offline preparation keeps the on-device privacy statement visible',
      (tester) async {
    await tester.pumpWidget(_page(OfflineNotice(
      enabled: true,
      readStatus: () async => const OfflineStatus(state: 'failed'),
    )));
    await tester.pump();
    expect(find.text('لم يكتمل الحفظ للتشغيل دون إنترنت'), findsOneWidget);
    expect(find.text('صورك وفيديوهاتك تبقى على جهازك.'), findsOneWidget);
    expect(find.text('تطبيق التحديث'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
