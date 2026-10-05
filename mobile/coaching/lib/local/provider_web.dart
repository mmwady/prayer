import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'contracts.dart';
import 'report_engine.dart';

@JS('iqtadiLocal.initialize')
external JSPromise<JSObject> _initialize();
@JS('iqtadiLocal.initializationProgress')
external JSObject _initializationProgress();
@JS('iqtadiLocal.analyze')
external JSPromise<JSObject> _analyze(JSUint8Array bytes);
@JS('iqtadiLocal.saveSession')
external JSPromise<JSAny?> _save(JSObject session);
@JS('iqtadiLocal.listSessions')
external JSPromise<JSArray<JSObject>> _list();
@JS('iqtadiLocal.loadSession')
external JSPromise<JSObject?> _load(JSString id);
@JS('iqtadiLocal.loadEvidence')
external JSPromise<JSUint8Array> _evidence(JSString session, JSString evidence);
@JS('iqtadiLocal.deleteSession')
external JSPromise<JSAny?> _delete(JSString id);
@JS('iqtadiLocal.exportSession')
external JSPromise<JSString> _export(JSString id);
@JS('iqtadiLocal.exportReport')
external JSPromise<JSString> _exportReport(JSObject data);
@JS('JSON.parse')
external JSObject _parse(JSString data);
@JS('Object.prototype.toString.call')
external String _objectTag(JSAny value);
Map<String, dynamic> _map(JSObject v) =>
    Map<String, dynamic>.from(v.dartify() as Map);
JSObject _json(Object value) => _parse(jsonEncode(value).toJS);
LocalInference createLocalInference() => WebLocalInference();
LocalSessionRepository createLocalRepository() => WebLocalRepository();
Future<String> exportSnapshot(Map<String, dynamic> data) async =>
    (await _exportReport(_json(data)).toDart).toDart;

class WebLocalInference
    implements LocalInference, InitializationProgressSource {
  @override
  Map<String, dynamic> get initializationProgress =>
      _map(_initializationProgress());
  @override
  Future<Map<String, dynamic>> initialize() async =>
      _map(await _initialize().toDart);
  @override
  Future<LocalFrameResult> analyze(Uint8List jpeg) async {
    final raw = await _analyze(jpeg.toJS).toDart;
    final preview = raw.getProperty<JSAny?>('preview_jpeg'.toJS);
    return LocalFrameResult(_map(raw.getProperty<JSObject>('result'.toJS)),
        landmarks: (raw.getProperty<JSArray<JSObject>>('landmarks'.toJS))
            .toDart
            .map(_map)
            .toList(),
        preview: preview != null && _objectTag(preview) == '[object Uint8Array]'
            ? (preview as JSUint8Array).toDart
            : null);
  }

  @override
  Future<Map<String, dynamic>> report(String p, List<Map<String, dynamic>> s,
          Map<String, dynamic> o) async =>
      buildLocalReport(p, s, o);
  @override
  Future<void>
      close() async {} // Shared browser worker is owned by the application.
}

class WebLocalRepository implements LocalSessionRepository {
  @override
  Future<void> save(Map<String, dynamic> m, Map<String, Uint8List> e) async {
    final value = _json(m);
    value.setProperty(
        'evidence'.toJS,
        e.entries
            .map((entry) {
              final item = _json({'id': entry.key});
              item.setProperty('bytes'.toJS, entry.value.toJS);
              return item;
            })
            .toList()
            .toJS);
    await _save(value).toDart;
  }

  @override
  Future<List<Map<String, dynamic>>> list() async =>
      (await _list().toDart).toDart.map(_map).toList();
  @override
  Future<Map<String, dynamic>?> load(String id) async {
    final value = await _load(id.toJS).toDart;
    return value == null ? null : _map(value);
  }

  @override
  Future<Uint8List> evidence(String s, String e) async =>
      (await _evidence(s.toJS, e.toJS).toDart).toDart;
  @override
  Future<void> delete(String id) async {
    await _delete(id.toJS).toDart;
  }

  @override
  Future<String> export(String id) async =>
      (await _export(id.toJS).toDart).toDart;
}
