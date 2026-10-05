import 'package:coaching/live/frame_store.dart';
import 'package:coaching/local/contracts.dart';
import 'package:coaching/local/provider_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('adaptive memory store bounds one frame and copies camera-owned bytes',
      () async {
    final store = MemoryLiveFrameStore(maxBytes: 3);
    await store.open();
    final bytes = Uint8List.fromList([1, 2, 3]);
    await store.put(0, bytes);
    bytes[0] = 99;
    expect(await store.read(0), [1, 2, 3]);
    await expectLater(store.put(1, Uint8List(1)), throwsStateError);
    await expectLater(store.put(0, Uint8List(4)), throwsStateError);
    expect(await store.read(0), [1, 2, 3]);
    await store.remove(0);
    await store.put(1, Uint8List.fromList([4]));
    await store.clear();
    await expectLater(store.read(1), throwsStateError);
  });

  test('eager previews do not invoke deferred renderer', () async {
    var calls = 0;
    final frame = LocalFrameResult({}, preview: Uint8List.fromList([7]),
        previewLoader: () async {
      calls++;
      return Uint8List.fromList([8]);
    });
    expect(await frame.loadPreview(), [7]);
    expect(calls, 0);
  });

  test(
      'native codec preserves doubles and renders only its matching deferred token',
      () async {
    const channel = MethodChannel('iqtadi/local_inference');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'analyze') {
        expect(call.arguments['defer_preview'], true);
        return <Object?, Object?>{
          'result': <Object?, Object?>{
            'confidence': .12345678901234567,
            'individual_models': <Object?>[
              <Object?, Object?>{
                'seed': '2026',
                'probabilities': <Object?, Object?>{'x': .9876543210987654}
              }
            ]
          },
          'preview_token': 42,
        };
      }
      expect(call.method, 'preview');
      expect(call.arguments['token'], 42);
      return Uint8List.fromList([3, 2, 1]);
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final frame = await NativeLocalInference().analyze(Uint8List.fromList([1]));
    expect(methods, ['analyze']);
    expect(frame.result['confidence'], .12345678901234567);
    expect((frame.result['individual_models'] as List).first,
        isA<Map<String, dynamic>>());
    expect(await frame.loadPreview(), [3, 2, 1]);
    expect(methods, ['analyze', 'preview']);
  });
}
