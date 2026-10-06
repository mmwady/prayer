import 'dart:convert';
import 'package:coaching/accounts/client.dart';
import 'package:coaching/accounts/codes.dart';
import 'package:coaching/accounts/controller.dart';
import 'package:coaching/accounts/family_screen.dart';
import 'package:coaching/accounts/mosque_groups_screen.dart';
import 'package:coaching/accounts/screen.dart';
import 'package:coaching/accounts/sync_adapter.dart';
import 'package:coaching/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const base = 'https://accounts.example.com';
final scope = Uri.encodeComponent(base);
final childKey = 'account_child_$scope';
final guardianKey = 'account_guardian_$scope';
final queueKey = 'account_queue_$scope';
Map<String, dynamic> result(String id) => {
      'client_attempt_id': id,
      'prayer': 'fajr',
      'performed_at': '2026-10-05T03:00:00Z',
      'valid': false,
      'sequence_valid': false,
      'uncertain': true,
      'rakats_expected': 2,
      'rakats_completed': 1,
      'analysis_version': 'existing-local-model',
      'movements_detected': 12,
      'movements_expected': 16,
      'movement_score': 75.0,
    };
Future<void> settleAsync() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

AccountController controller(http.Client httpClient) => AccountController(
      client: AccountClient(base, client: httpClient),
      tokenReader: (key) async => key == childKey ? 'device-session' : null,
      tokenWriter: (key, value) async {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    PrayerSyncAdapter.binding = null;
    PrayerSyncAdapter.sink = null;
  });
  test(
      'offline queue persists restart, retries same id, and only scalar fields leave',
      () async {
    SharedPreferences.setMockInitialValues({
      childKey: jsonEncode({'child_id': 'omar', 'name': 'Omar'})
    });
    bool online = false, loseAck = true;
    final requests = <Map<String, dynamic>>[];
    final accepted = <String>{};
    http.Client transport() => MockClient((request) async {
          if (!online) throw http.ClientException('offline');
          if (request.url.path.endsWith('/device')) {
            return http.Response(
                jsonEncode({'child_id': 'omar', 'name': 'Omar'}), 200);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          accepted.add(body['client_attempt_id']);
          if (loseAck) {
            loseAck = false;
            throw http.ClientException('lost ACK after commit');
          }
          return http.Response(
              jsonEncode({'id': 'saved', 'duplicate': true}), 200);
        });
    var c = controller(transport());
    await c.initialize();
    await settleAsync();
    await PrayerSyncAdapter.completed(c.binding, {
      ...result('attempt-1'),
      'landmarks': [1, 2],
      'image': 'private',
      'features': [0]
    });
    await settleAsync();
    expect(c.queue, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(queueKey), isNot(contains('landmarks')));
    expect(c.queue.single['payload']['uncertain'], isTrue);
    expect(c.queue.single['payload']['movement_score'], 75.0);
    c.dispose();
    c = controller(transport());
    await c.initialize();
    await settleAsync();
    expect(c.child!['name'], 'Omar');
    expect(c.queue, hasLength(1));
    online = true;
    await c.sync();
    expect(c.queue, hasLength(1));
    await c.sync();
    expect(c.queue, isEmpty);
    expect(accepted, {'attempt-1'});
    expect(requests, hasLength(2));
    expect(requests[0], requests[1]);
    expect(requests.first.keys, isNot(contains('image')));
    expect(requests.first['movements_detected'], 12);
    expect(requests.first['movements_expected'], 16);
    expect(requests.first['movement_score'], 75.0);
    c.dispose();
  });
  test('unpaired devices, demo and wrong child binding do not enqueue',
      () async {
    SharedPreferences.setMockInitialValues({});
    int network = 0;
    final c = controller(MockClient((r) async {
      network++;
      return http.Response('{}', 200);
    }));
    await c.initialize();
    await settleAsync();
    await PrayerSyncAdapter.completed(null, result('guest'));
    expect(network, 0);
    expect(c.queue, isEmpty);
    c.child = {'child_id': 'omar', 'name': 'Omar'};
    await c.enqueue('$scope|other', result('wrong'));
    await c.enqueue(c.binding!, {...result('demo'), 'prayer': 'demo'});
    expect(c.queue, isEmpty);
    c.dispose();
  });
  test(
      'revoked session retains pending results and never reassigns to new child',
      () async {
    SharedPreferences.setMockInitialValues({
      childKey: jsonEncode({'child_id': 'omar', 'name': 'Omar'}),
      queueKey: jsonEncode([
        {'binding': '$scope|omar', 'payload': result('one')}
      ])
    });
    int submits = 0;
    final c = controller(MockClient((r) async {
      if (r.url.path.endsWith('/attempts')) submits++;
      return http.Response('{"detail":"DEVICE_DISCONNECTED"}', 401);
    }));
    await c.initialize();
    await settleAsync();
    expect(c.child, isNull);
    expect(c.queue, hasLength(1));
    c.child = {'child_id': 'ali', 'name': 'Ali'};
    await c.sync();
    expect(submits, 0);
    expect(c.queue, hasLength(1));
    c.dispose();
  });
  test('serialized concurrent enqueue avoids duplicates', () async {
    SharedPreferences.setMockInitialValues({
      childKey: jsonEncode({'child_id': 'omar', 'name': 'Omar'})
    });
    final c = controller(
        MockClient((_) async => throw http.ClientException('offline')));
    await c.initialize();
    await settleAsync();
    await Future.wait([
      c.enqueue(c.binding!, result('same')),
      c.enqueue(c.binding!, result('same')),
      c.enqueue(c.binding!, result('other'))
    ]);
    expect(c.queue, hasLength(2));
    await expectLater(
        c.enqueue(c.binding!, {
          ...result('nested'),
          'analysis_version': [1, 2, 3]
        }),
        throwsFormatException);
    c.dispose();
  });
  test('one login also binds the adult self profile for camera practice',
      () async {
    SharedPreferences.setMockInitialValues({});
    final written = <String, String?>{};
    final requests = <http.Request>[];
    final c = AccountController(
      client: AccountClient(
        base,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
              jsonEncode({
                'session_token': 'account-session',
                'guardian': {
                  'id': 'user-1',
                  'name': 'Mohamed',
                  'email': 'demo@example.com',
                  'role': 'MEMBER'
                },
                'practice_profile': {
                  'child_id': 'profile-user-1',
                  'name': 'Mohamed',
                  'device_id': 'device-1',
                  'profile_kind': 'SELF'
                },
                'practice_session_token': 'practice-session'
              }),
              200);
        }),
      ),
      tokenReader: (_) async => null,
      tokenWriter: (key, value) async => written[key] = value,
    );
    await c.initialize();
    await c.authenticate('demo@example.com', 'IqtadiDemo!2026');
    expect(c.guardian!['role'], 'MEMBER');
    expect(c.child!['profile_kind'], 'SELF');
    expect(c.binding, '$scope|profile-user-1');
    expect(
        written.values, containsAll(['account-session', 'practice-session']));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body.keys, isNot(contains('role')));
    c.dispose();
  });
  test(
      'pairing URL is detected without choosing a code type and persists child',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Map<String, dynamic>>[];
    const url = 'https://app.example/#pair=one-time-secret';
    final c = AccountController(
      client: AccountClient(
        base,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/device/progress')) {
            return http.Response(
                '{"weekly_points":31,"weekly_valid_prayers":5,"streak":2,"valid_prayers":3}',
                200);
          }
          if (request.url.path.endsWith('/device')) {
            return http.Response(
                '{"child_id":"child-1","name":"Omar","profile_kind":"DEPENDENT"}',
                200);
          }
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
              jsonEncode({
                'session_token': 'child-session',
                'child_id': 'child-1',
                'name': 'Omar',
                'device_id': 'phone-1',
                'profile_kind': 'DEPENDENT'
              }),
              200);
        }),
      ),
      tokenReader: (_) async => null,
      tokenWriter: (_, __) async {},
      startupPairingCode: url,
    );
    await c.initialize();
    await settleAsync();
    expect(normalizeAccountCode(url), 'iqtadi-pair:one-time-secret');
    expect(detectAccountCodeKind(url), 'DEVICE');
    expect(requests.single['token'], 'iqtadi-pair:one-time-secret');
    expect(c.child!['profile_kind'], 'DEPENDENT');
    expect(c.childProgress!['weekly_points'], 31);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(childKey), contains('DEPENDENT'));
    c.dispose();
  });
  test('logout clears cached identity when the server session is already gone',
      () async {
    SharedPreferences.setMockInitialValues({});
    var loggedIn = false;
    final written = <String, String?>{};
    final c = AccountController(
      client: AccountClient(
        base,
        client: MockClient((request) async {
          if (!loggedIn &&
              request.method == 'POST' &&
              request.url.path.endsWith('/session')) {
            loggedIn = true;
            return http.Response(
                jsonEncode({
                  'session_token': 'account-session',
                  'guardian': {
                    'id': 'demo-user',
                    'name': 'Mohamed',
                    'email': 'demo@example.com',
                    'role': 'MEMBER'
                  },
                  'practice_profile': {
                    'child_id': 'profile-demo-user',
                    'name': 'Mohamed',
                    'device_id': 'device-demo',
                    'profile_kind': 'SELF'
                  },
                  'practice_session_token': 'practice-session'
                }),
                200);
          }
          return http.Response('{"detail":"SIGN_IN_REQUIRED"}', 401);
        }),
      ),
      tokenReader: (_) async => null,
      tokenWriter: (key, value) async => written[key] = value,
    );
    await c.initialize();
    await c.authenticate('demo@example.com', 'IqtadiDemo!2026');
    expect(c.guardian, isNotNull);
    expect(c.child, isNotNull);

    await c.logout();

    expect(c.guardian, isNull);
    expect(c.child, isNull);
    expect(written[guardianKey], isNull);
    expect(written[childKey], isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(guardianKey), isFalse);
    expect(prefs.containsKey(childKey), isFalse);
    c.dispose();
  });
  test('development signup is honest and waits for verification', () async {
    SharedPreferences.setMockInitialValues({});
    final paths = <String>[];
    final c = AccountController(
      client: AccountClient(
        base,
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/auth/signup')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect((body['password'] as String).length, 8);
            return http.Response(
                '{"message":"CHECK_EMAIL","delivery":"development_outbox"}',
                200);
          }
          return http.Response('{}', 500);
        }),
      ),
      tokenReader: (_) async => null,
      tokenWriter: (_, __) async {},
    );
    await c.initialize();
    await c.authenticate('local.parent@example.com', 'Pass123!',
        fullName: 'Local Parent');
    expect(paths, ['/api/v1/accounts/auth/signup']);
    expect(c.guardian, isNull);
    expect(c.error, contains('لم يُرسل بريد'));
    c.dispose();
  });
  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets('unified account and separate code entry at width $width',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = controller(MockClient((_) async => http.Response('{}', 200)));
      c.ready = true;
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: c,
          child: MaterialApp(
              theme: buildAppTheme(),
              home: const Directionality(
                  textDirection: TextDirection.rtl, child: AccountScreen()))));
      await tester.pumpAndSettle();
      expect(find.text('تسجيل الدخول'), findsAtLeastNWidgets(1));
      expect(find.text('إنشاء حساب جديد'), findsOneWidget);
      expect(find.text('لدي رمز دعوة أو ربط جهاز'), findsOneWidget);
      expect(find.text('ولي أمر / معلم'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets('family and mosque dashboards fit a narrow phone',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = controller(MockClient((request) async {
      final path = request.url.path;
      Object value;
      if (path.endsWith('/families')) {
        value = [
          {'id': 'family-1', 'name': 'أسرة محمد', 'role': 'OWNER'}
        ];
      } else if (path.endsWith('/families/family-1/progress')) {
        value = {
          'leaderboard': [
            {'name': 'عمر', 'weekly_points': 31, 'weekly_valid_prayers': 5}
          ]
        };
      } else if (path.endsWith('/families/family-1')) {
        value = {
          'family': {'id': 'family-1', 'name': 'أسرة محمد', 'role': 'OWNER'},
          'members': [
            {'id': 'user-1', 'name': 'محمد', 'role': 'OWNER'}
          ],
          'dependents': [
            {
              'id': 'child-1',
              'name': 'عمر',
              'alias': 'النجم',
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
              'alias': 'النجم',
              'attendance': {'attended': 4, 'eligible': 5, 'rate': .8}
            }
          ],
          'practice_leaderboard': [
            {
              'alias': 'النجم',
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
          home: Directionality(textDirection: TextDirection.rtl, child: home),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await pump(const FamilyScreen());
    expect(find.text('أسرة محمد'), findsWidgets);
    expect(find.text('إضافة طفل'), findsOneWidget);
    expect(find.text('إدارة/فصل الأجهزة'), findsOneWidget);
    await pump(const MosqueGroupsScreen());
    await tester.tap(find.text('وضع قائد المسجد'));
    await tester.pumpAndSettle();
    expect(find.text('عرض QR للانضمام'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('قبول الطفل'), 300);
    expect(find.text('رفض الطلب'), findsOneWidget);
    expect(find.text('قبول الطفل'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('لوحة الحضور'), 300);
    expect(find.text('لوحة الحضور'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
