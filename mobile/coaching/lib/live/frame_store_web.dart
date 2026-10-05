import 'dart:js_interop';
import 'dart:typed_data';
import 'frame_store.dart';

@JS('iqtadiLive.storageVersion')
external JSNumber? get _storageVersion;

@JS('iqtadiLive.openStore')
external JSPromise<JSString> _open();
@JS('iqtadiLive.putFrame')
external JSPromise<JSAny?> _put(
    JSString session, JSNumber index, JSUint8Array bytes);
@JS('iqtadiLive.readFrame')
external JSPromise<JSUint8Array> _read(JSString session, JSNumber index);
@JS('iqtadiLive.removeFrame')
external JSPromise<JSAny?> _remove(JSString session, JSNumber index);
@JS('iqtadiLive.clearStore')
external JSPromise<JSAny?> _clear(JSString session);

LiveFrameStore createLiveFrameStore() => WebFrameStore();

class WebFrameStore implements LiveFrameStore {
  String? _session;
  @override
  Future<void> open() async {
    if ((_storageVersion?.toDartInt ?? 0) != 1) {
      throw StateError(
          'ملفات الويب المحملة لا تطابق نسخة التطبيق. أعد تحميل الصفحة بالكامل باستخدام Ctrl+Shift+R؛ Hot Restart وحده لا يحدث ملفات الكاميرا.');
    }
    await clear();
    _session = (await _open().toDart).toDart;
  }

  @override
  Future<void> put(int index, Uint8List bytes) async =>
      await _put(_session!.toJS, index.toJS, bytes.toJS).toDart;
  @override
  Future<Uint8List> read(int index) async =>
      (await _read(_session!.toJS, index.toJS).toDart).toDart;
  @override
  Future<void> remove(int index) async =>
      await _remove(_session!.toJS, index.toJS).toDart;
  @override
  Future<void> clear() async {
    if (_session != null) await _clear(_session!.toJS).toDart;
    _session = null;
  }
}
