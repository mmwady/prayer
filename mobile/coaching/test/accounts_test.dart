import 'dart:convert';
import 'package:coaching/accounts/client.dart';
import 'package:coaching/accounts/controller.dart';
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
  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets('optional account and guaranteed manual code at width $width',
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
      expect(find.text('رمز الربط المؤقت'), findsOneWidget);
      expect(find.text('ربط الجهاز'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
