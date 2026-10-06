import 'dart:convert';
import 'package:coaching/accounts/family_screen.dart';
import 'package:coaching/accounts/mosque_groups_screen.dart';
import 'package:coaching/accounts/screen.dart';
import 'package:coaching/l10n/app_localizations.dart';
import 'package:coaching/state/locale_provider.dart';
import 'package:coaching/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'accounts_test.dart' show controller;

const delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate
];
void main() {
  testWidgets(
      'English integrated family and mosque dashboards preserve user data',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = controller(MockClient((request) async {
      final path = request.url.path;
      Object value;
      if (path.endsWith('/families')) {
        value = [
          {'id': 'family-1', 'name': 'الفجر', 'role': 'OWNER'}
        ];
      } else if (path.endsWith('/families/family-1/progress')) {
        value = {
          'leaderboard': [
            {'name': 'عمر', 'weekly_points': 31, 'weekly_valid_prayers': 5}
          ]
        };
      } else if (path.endsWith('/families/family-1')) {
        value = {
          'family': {'id': 'family-1', 'name': 'الفجر', 'role': 'OWNER'},
          'members': [
            {'id': 'user-1', 'name': 'محمد', 'role': 'OWNER'}
          ],
          'dependents': [
            {
              'id': 'child-1',
              'name': 'عمر',
              'alias': 'القيام',
              'age_band': 'CHILD_5_9'
            }
          ]
        };
      } else if (path.endsWith('/children/child-1/devices')) {
        value = [];
      } else if (path.endsWith('/mosque-groups')) {
        value = [
          {
            'id': 'group-1',
            'name': 'براعم الفجر',
            'mosque_name': 'مسجد الرحمة',
            'access': 'LEADER'
          }
        ];
      } else if (path.endsWith('/overview')) {
        value = {
          'practice_profile': {'id': 'self-1', 'name': 'محمد'},
          'families': [],
          'joined_groups': []
        };
      } else if (path.endsWith('/mosques')) {
        value = [
          {
            'id': 'mosque-1',
            'name': 'مسجد الرحمة',
            'city': 'الرياض',
            'role': 'LEADER'
          }
        ];
      } else if (path.endsWith('/mosque-groups/group-1/dashboard')) {
        value = {
          'group': {
            'id': 'group-1',
            'name': 'براعم الفجر',
            'mosque_id': 'mosque-1',
            'mosque_name': 'مسجد الرحمة',
            'city': 'الرياض'
          },
          'access': 'LEADER',
          'privacy': 'الأسماء الحقيقية لا تظهر للمجموعة.',
          'pending_members': [
            {
              'profile_id': 'child-pending',
              'alias': 'الفجر الصغير',
              'joined_at': '2026-10-06T10:00:00Z'
            }
          ],
          'attendance_sessions': [],
          'attendance_leaderboard': [
            {
              'profile_id': 'child-1',
              'alias': 'القيام',
              'attendance': {'attended': 4, 'eligible': 5, 'rate': .8}
            }
          ],
          'practice_leaderboard': [
            {
              'alias': 'القيام',
              'practice': {'weekly_valid_prayers': 5, 'weekly_points': 31}
            }
          ]
        };
      } else if (path.endsWith('/mosques/mosque-1/leaderboard')) {
        value = {
          'groups': [
            {
              'group_name': 'براعم الفجر',
              'member_count': 8,
              'attendance_rate': .8
            }
          ]
        };
      } else {
        return http.Response('{"detail":"NOT_FOUND"}', 404);
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(value)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));
    c.ready = true;
    c.guardian = {'id': 'user-1', 'name': 'محمد'};
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pump(Widget home) async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
          theme: buildAppTheme(),
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: delegates,
          home: Directionality(textDirection: TextDirection.ltr, child: home),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final data = [
        'الفجر',
        'القيام',
        'محمد',
        'عمر',
        'براعم الفجر',
        'مسجد الرحمة',
        'الرياض',
        'الفجر الصغير'
      ]..sort((a, b) => b.length.compareTo(a.length));
      final untranslated = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .map((text) {
            for (final value in data) {
              text = text.replaceAll(value, '');
            }
            return text;
          })
          .where((text) => RegExp(r'[\u0600-\u06ff]').hasMatch(text))
          .toList();
      expect(untranslated, isEmpty);
    }

    for (final width in [320.0, 390.0, 1024.0]) {
      tester.view.physicalSize = Size(width, 900);
      await pump(const FamilyScreen());
      expect(find.text('الفجر'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Add a child'), 250);
      expect(find.text('Add a child'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.text('Manage / disconnect devices'), 250);
      expect(find.text('Manage / disconnect devices'), findsOneWidget);
      await pump(const MosqueGroupsScreen());
      await tester.tap(find.text('Mosque leader mode'));
      await tester.pumpAndSettle();
      expect(find.text('Show joining QR'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Accept child'), 300);
      expect(find.text('Reject request'), findsOneWidget);
      expect(find.text('Accept child'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final data = [
        'الفجر',
        'القيام',
        'محمد',
        'عمر',
        'براعم الفجر',
        'مسجد الرحمة',
        'الرياض',
        'الفجر الصغير'
      ]..sort((a, b) => b.length.compareTo(a.length));
      final untranslated = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .map((text) {
            for (final value in data) {
              text = text.replaceAll(value, '');
            }
            return text;
          })
          .where((text) => RegExp(r'[\u0600-\u06ff]').hasMatch(text))
          .toList();
      expect(untranslated, isEmpty);
      await tester.scrollUntilVisible(find.text('Attendance dashboard'), 300);
      expect(find.text('Attendance dashboard'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
      'changing locale retains the unified account form state and input',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final account =
        controller(MockClient((_) async => http.Response('{}', 200)))
          ..ready = true;
    final language = LocaleProvider();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider.value(value: language),
        ],
        child: Consumer<LocaleProvider>(
            builder: (context, locale, child) => MaterialApp(
                  locale: locale.locale,
                  supportedLocales: const [Locale('ar'), Locale('en')],
                  localizationsDelegates: delegates,
                  theme: buildAppTheme(),
                  home: const AccountScreen(),
                ))));
    await tester.pumpAndSettle();
    final screen = tester.state(find.byType(AccountScreen));
    await tester.enterText(
        find.byType(TextFormField).at(0), 'private@example.com');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'unchanged-password');
    await language.setLocale('en');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(AccountScreen)), same(screen));
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('I have an invitation or device pairing code'),
        findsOneWidget);
    expect(find.text('private@example.com'), findsOneWidget);
    expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .last
            .controller!
            .text,
        'unchanged-password');
    await language.setLocale('ar');
    await tester.pumpAndSettle();
    expect(find.text('الحساب'), findsOneWidget);
    expect(find.text('private@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
    language.dispose();
  });
}
