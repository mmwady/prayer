import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:coaching/live/camera_source.dart';
import 'package:coaching/live/live_client.dart';
import 'package:coaching/live/live_controller.dart';
import 'package:coaching/live/socket.dart';
import 'package:coaching/live/frame_store.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/screens/live_analysis_screen.dart';
import 'package:coaching/video/video_source.dart';
import 'video_analysis_test.dart' as fixtures;

class FakeCamera implements LiveCamera {
  bool opened = false, streaming = false, awake = false;
  bool front = true, failSwitch = false;
  Completer<void>? opening;
  void Function(int, Uint8List)? callback;
  bool Function()? shouldCapture;
  @override
  bool get ready => opened;
  @override
  Future<void> open({bool front = true, bool requireDirection = false}) async {
    await opening?.future;
    if (requireDirection && failSwitch) throw StateError('camera unavailable');
    this.front = front;
    opened = true;
  }

  @override
  Widget preview() => const ColoredBox(color: Colors.black);
  @override
  Future<void> capture(double fps, int maxDimension,
      void Function(int, Uint8List) onFrame, void Function(Object) onError,
      {bool Function()? shouldCapture}) async {
    streaming = true;
    callback = onFrame;
    this.shouldCapture = shouldCapture;
  }

  void frame(int timestamp) {
    if (shouldCapture?.call() != false) {
      callback!(timestamp, Uint8List.fromList([1, 2, 3]));
    }
  }

  @override
  Future<void> stop() async => streaming = false;
  @override
  Future<bool> keepAwake(bool enabled) async {
    awake = enabled;
    return true;
  }

  @override
  Future<void> close() async {
    await stop();
    opened = false;
  }
}

class MemoryStore implements LiveFrameStore {
  final frames = <int, Uint8List>{};
  bool failWrites = false;
  @override
  Future<void> open() async => frames.clear();
  @override
  Future<void> put(int index, Uint8List bytes) async {
    if (failWrites) throw StateError('storage full');
    frames[index] = bytes;
  }

  @override
  Future<Uint8List> read(int index) async => frames[index]!;
  @override
  Future<void> remove(int index) async => frames.remove(index);
  @override
  Future<void> clear() async => frames.clear();
}

class FakeSocket implements LiveSocket {
  final packets = <Uint8List>[];
  final ids = <int>{};
  Completer<void>? held;
  int failTimes = 0, connections = 0;
  Uri? url;
  String? token;
  bool closed = false;
  @override
  Future<void> connect(Uri url, String token) async {
    connections++;
    this.url = url;
    this.token = token;
    closed = false;
  }

  @override
  Future<Map<String, dynamic>> send(Uint8List packet) async {
    packets.add(packet);
    final length = ByteData.sublistView(packet).getUint32(0);
    final header = jsonDecode(utf8.decode(packet.sublist(4, 4 + length)));
    ids.add(header['sequence_index']
        as int); // Server may process before ACK is lost.
    await held?.future;
    if (failTimes-- > 0) throw StateError('ACK lost');
    return {
      'type': 'ack',
      'frame_id': header['frame_id'],
      'uploaded_frames': ids.length,
      'processed_frames': ids.length
    };
  }

  @override
  Future<void> close() async {
    closed = true;
    held?.complete();
    held = null;
  }
}

LiveAnalysisClient api(FakeSocket socket, List<String> operations) =>
    LiveAnalysisClient(
        socket: socket,
        baseUrl: 'https://backend.example',
        client: MockClient((request) async {
          operations.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/config')) {
            return fixtures.jsonResponse({
              ...fixtures.config,
              'live_enabled': true,
              'live_modes': ['buffered', 'adaptive'],
              'live_buffer_bytes': 480000000
            });
          }
          if (request.method == 'DELETE') return fixtures.jsonResponse({}, 204);
          if (request.url.path.endsWith('/live')) {
            return fixtures.jsonResponse(
                {'job_id': 'job', 'access_token': 'private-owner'}, 201);
          }
          if (request.url.path.endsWith('/report')) {
            return fixtures.jsonResponse(fixtures.fixture());
          }
          return fixtures.jsonResponse({});
        }));

Future<void> spinUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

void main() {
  test(
      'camera switching is serialized, preserves setup and blocks live capture',
      () async {
    final camera = FakeCamera(), socket = FakeSocket();
    final operations = <String>[];
    final controller =
        LiveController(camera: camera, api: api(socket, operations));
    await controller.switchCamera();
    expect(camera.ready, false);
    await controller.open();
    final configRequests = operations.length;
    camera.opening = Completer<void>();
    final switching = controller.switchCamera();
    expect(controller.opening, true);
    await controller.switchCamera();
    await controller.start('demo', consent: true);
    expect(camera.streaming, false);
    camera.opening!.complete();
    await switching;
    camera.opening = null;
    expect(camera.front, false);
    expect(controller.frontCamera, false);
    expect(operations.length, configRequests);
    await controller.switchCamera();
    expect(camera.front, true);
    camera.failSwitch = true;
    await controller.switchCamera();
    expect(controller.frontCamera, true);
    expect(controller.opening, false);
    expect(controller.error, contains('تعذر تبديل الكاميرا'));
    expect(camera.ready, true);
    camera.failSwitch = false;
    await controller.start('demo', consent: true, scenario: 'normal');
    await controller.switchCamera();
    expect(camera.front, true);
    expect(camera.streaming, true);
    await controller.cancel();
    controller.dispose();
  });

  test('packet preserves JPEG and original time without exposing token', () {
    final frame = SampledFrame(8, 2345, Uint8List.fromList([255, 216, 4]));
    final bytes = LiveAnalysisClient.packet(frame);
    final length = ByteData.sublistView(bytes).getUint32(0);
    expect(jsonDecode(utf8.decode(bytes.sublist(4, 4 + length))),
        {'frame_id': 'live_8', 'sequence_index': 8, 'timestamp_ms': 2345});
    expect(bytes.sublist(4 + length), frame.jpeg);
  });

  test('consent gates network/capture; finish waits for ACK before report',
      () async {
    final camera = FakeCamera(), socket = FakeSocket();
    final operations = <String>[];
    final controller =
        LiveController(camera: camera, api: api(socket, operations));
    await controller.open();
    await controller.start('demo', consent: false);
    expect(camera.streaming, false);
    expect(operations.where((r) => r.startsWith('POST')), isEmpty);
    await controller.start('demo', consent: true, scenario: 'normal');
    expect(camera.awake && camera.streaming, true);
    expect(socket.url!.scheme, 'wss');
    expect(socket.url!.query, isEmpty);
    expect(socket.token, 'private-owner');
    socket.held = Completer();
    camera.frame(250);
    await spinUntil(() => socket.packets.isNotEmpty);
    final finishing = controller.finish();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(operations.any((r) => r.endsWith('/complete')), false);
    socket.held!.complete();
    socket.held = null;
    await finishing;
    expect(controller.phase, LivePhase.completed);
    expect(controller.processed, 1);
    expect(camera.streaming || camera.awake || camera.ready, false);
    expect(operations.indexWhere((r) => r.endsWith('/complete')),
        lessThan(operations.indexWhere((r) => r.endsWith('/report'))));
    await controller.cancel();
    controller.dispose();
  });

  test('lost ACK reconnects and retransmits identical frame', () async {
    final camera = FakeCamera(), socket = FakeSocket()..failTimes = 1;
    final controller = LiveController(
        camera: camera, api: api(socket, []), retryDelay: Duration.zero);
    await controller.open();
    await controller.start('demo', consent: true, scenario: 'normal');
    camera.frame(250);
    await spinUntil(() => controller.processed == 1);
    expect(socket.connections, 2);
    expect(socket.packets, hasLength(2));
    expect(socket.packets[0], socket.packets[1]);
    expect(controller.uploaded, 1);
    await controller.cancel();
    controller.dispose();
  });

  test('buffered mode preserves every sampled frame during slow ACK', () async {
    final camera = FakeCamera(), socket = FakeSocket();
    final controller = LiveController(camera: camera, api: api(socket, []));
    await controller.open();
    await controller.start('demo', consent: true, scenario: 'normal');
    socket.held = Completer();
    for (var i = 1; i <= 60; i++) {
      camera.frame(i * 250);
    }
    await spinUntil(() => socket.packets.isNotEmpty);
    expect(controller.pending, 60);
    expect(controller.dropped, 0);
    socket.held!.complete();
    socket.held = null;
    await controller.finish();
    expect(socket.ids, {for (var i = 0; i < 60; i++) i});
    expect(controller.processed, 60);
    await controller.cancel();
    controller.dispose();
  });

  test('adaptive mode gates capture before encoding while ACK is pending',
      () async {
    final camera = FakeCamera(), socket = FakeSocket();
    final controller = LiveController(camera: camera, api: api(socket, []))
      ..mode = LiveMode.adaptive;
    await controller.open();
    await controller.start('demo', consent: true, scenario: 'normal');
    socket.held = Completer();
    for (var i = 0; i < 60; i++) {
      camera.frame(i * 250);
    }
    await spinUntil(() => socket.packets.isNotEmpty);
    expect(controller.captured, 1);
    expect(controller.pending, 1);
    expect(controller.dropped, 0);
    socket.held!.complete();
    socket.held = null;
    await spinUntil(() => controller.pending == 0);
    camera.frame(15250);
    await controller.finish();
    expect(socket.ids, {0, 1});
    await controller.cancel();
    controller.dispose();
  });

  test('local frame remains saved until ACK and cancel removes pending files',
      () async {
    final camera = FakeCamera(), socket = FakeSocket(), store = MemoryStore();
    final controller =
        LiveController(camera: camera, api: api(socket, []), store: store);
    await controller.open();
    await controller.start('demo', consent: true, scenario: 'normal');
    socket.held = Completer();
    camera.frame(250);
    await spinUntil(() => socket.packets.isNotEmpty);
    expect(store.frames.keys, [0]);
    expect(controller.uploaded, 0);
    await controller.cancel();
    expect(store.frames, isEmpty);
    controller.dispose();
  });

  test(
      'storage failure stops capture explicitly without issuing partial report',
      () async {
    final camera = FakeCamera(),
        socket = FakeSocket(),
        store = MemoryStore()..failWrites = true;
    final operations = <String>[];
    final controller = LiveController(
        camera: camera, api: api(socket, operations), store: store);
    await controller.open();
    await controller.start('demo', consent: true, scenario: 'normal');
    camera.frame(250);
    await spinUntil(() => controller.phase == LivePhase.failed);
    expect(controller.error, contains('تعذر حفظ صورة'));
    expect(socket.packets, isEmpty);
    await controller.finish();
    expect(operations.any((r) => r.endsWith('/complete')), false);
    await controller.cancel();
    controller.dispose();
  });

  test('buffered completion polls until all server frames are analyzed',
      () async {
    final camera = FakeCamera(), socket = FakeSocket();
    var polls = 0, reportRequested = false;
    final client = LiveAnalysisClient(
        socket: socket,
        baseUrl: 'https://backend.example',
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/config')) {
            return fixtures.jsonResponse({
              ...fixtures.config,
              'live_enabled': true,
              'live_modes': ['buffered', 'adaptive']
            });
          }
          if (request.method == 'DELETE') return fixtures.jsonResponse({}, 204);
          if (path.endsWith('/live')) {
            expect(jsonDecode(request.body)['mode'], 'buffered');
            return fixtures.jsonResponse(
                {'job_id': 'job', 'access_token': 'private-owner'}, 201);
          }
          if (path.endsWith('/complete')) {
            return fixtures.jsonResponse({
              'status': 'PROCESSING',
              'uploaded_frames': 1,
              'processed_frames': 0
            }, 202);
          }
          if (path.endsWith('/report')) {
            reportRequested = true;
            expect(polls, 2);
            return fixtures.jsonResponse(fixtures.fixture());
          }
          polls++;
          return fixtures.jsonResponse({
            'status': polls == 1 ? 'PROCESSING' : 'COMPLETED',
            'uploaded_frames': 1,
            'processed_frames': polls == 1 ? 0 : 1
          });
        }));
    final controller = LiveController(
        camera: camera,
        api: client,
        store: MemoryStore(),
        pollDelay: Duration.zero);
    await controller.open();
    await controller.start('demo', consent: true, scenario: 'normal');
    camera.frame(250);
    await controller.finish();
    expect(reportRequested, true);
    expect(controller.serverPending, 0);
    expect(controller.phase, LivePhase.completed);
    await controller.cancel();
    controller.dispose();
  });

  test('cancel during in-flight frame releases camera/socket and deletes job',
      () async {
    final camera = FakeCamera(), socket = FakeSocket();
    final operations = <String>[];
    final controller =
        LiveController(camera: camera, api: api(socket, operations));
    await controller.open();
    await controller.start('demo', consent: true, scenario: 'normal');
    socket.held = Completer();
    camera.frame(250);
    await spinUntil(() => socket.packets.isNotEmpty);
    await controller.cancel();
    expect(controller.phase, LivePhase.cancelled);
    expect(controller.pending, 0);
    expect(camera.ready || camera.streaming || camera.awake, false);
    expect(operations.last, 'DELETE /api/v1/prayer-analyses/job');
    controller.dispose();
  });

  testWidgets('live screen requires explicit camera open and consent',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final camera = FakeCamera(), socket = FakeSocket();
    final controller = LiveController(
        camera: camera, api: api(socket, []), store: MemoryStore());
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: LiveAnalysisScreen(
                definition: PrayerCatalog.of(PrayerType.demo),
                controller: controller))));
    expect(camera.ready, false);
    expect(find.byTooltip('تبديل الكاميرا'), findsNothing);
    await tester.tap(find.text('فتح الكاميرا وضبط المكان'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'محاكاة تحليل — النتائج اصطناعية وليست تحليلًا فعليًا للكاميرا'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.byTooltip('تبديل الكاميرا'), 150);
    await tester.tap(find.byTooltip('تبديل الكاميرا'));
    await tester.pumpAndSettle();
    expect(camera.front, false);
    await tester.tap(find.byTooltip('تبديل الكاميرا'));
    await tester.pumpAndSettle();
    expect(camera.front, true);
    await tester.scrollUntilVisible(find.text('ابدأ التحليل المباشر'), 200);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'ابدأ التحليل المباشر'));
    expect(button.onPressed, isNull);
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 150);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('ابدأ التحليل المباشر'), -150);
    await tester.tap(find.text('ابدأ التحليل المباشر'));
    await tester.pump();
    expect(find.text('5'), findsNWidgets(2));
    expect(camera.streaming, false);
    for (var remaining = 4; remaining >= 0; remaining--) {
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('$remaining'), findsNWidgets(2));
      expect(camera.streaming, false);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !camera.streaming; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(camera.streaming, true, reason: controller.error);
    unawaited(controller.cancel());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
