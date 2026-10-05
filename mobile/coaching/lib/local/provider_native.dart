import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'contracts.dart';
import 'report_engine.dart';

const _channel = MethodChannel('iqtadi/local_inference');
Future<Map<String, dynamic>>? _initializing;
Future<Map<String, dynamic>> _initialize() => _initializing ??=
        _channel.invokeMapMethod<String, dynamic>('initialize').then((v) {
      if (v == null) throw StateError('تعذر تهيئة النماذج المحلية');
      return v;
    }).catchError((Object e) {
      _initializing = null;
      throw StateError('تعذر تهيئة النماذج المحلية على هذا الجهاز: $e');
    });
LocalInference createLocalInference() => NativeLocalInference();
LocalSessionRepository createLocalRepository() => NativeLocalRepository();
Future<String> exportSnapshot(Map<String, dynamic> data) async {
  final saved = await _channel.invokeMethod<bool>('export', {
    'name': 'iqtadi-${data['id']}.json',
    'json': const JsonEncoder.withIndent('  ').convert(data)
  });
  return saved == true
      ? 'تم تصدير التقرير إلى الملف الذي اخترته'
      : 'أُلغي التصدير';
}

class NativeLocalInference implements LocalInference {
  @override
  Future<Map<String, dynamic>> initialize() => _initialize();
  @override
  Future<LocalFrameResult> analyze(Uint8List jpeg) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
        'analyze', {'jpeg': jpeg, 'defer_preview': true});
    if (raw == null) throw StateError('لم يُرجع المحرك نتيجة');
    return LocalFrameResult(_nativeValue(raw['result']) as Map<String, dynamic>,
        landmarks: ((_nativeValue(raw['landmarks']) as List?) ?? const [])
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList(),
        preview: raw['preview_jpeg'] as Uint8List?,
        previewLoader: raw['preview_token'] is int
            ? () => _channel.invokeMethod<Uint8List>(
                'preview', {'token': raw['preview_token']})
            : null);
  }

  @override
  Future<Map<String, dynamic>> report(String p, List<Map<String, dynamic>> s,
          Map<String, dynamic> o) async =>
      buildLocalReport(p, s, o);
  @override
  Future<void>
      close() async {} // Application owns shared native inference sessions.
}

// StandardMessageCodec already preserves doubles. Convert nested map types
// directly, avoiding a JSON string and a second complete prediction allocation.
Object? _nativeValue(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries) e.key as String: _nativeValue(e.value)
    };
  }
  if (value is List) return value.map(_nativeValue).toList(growable: false);
  return value;
}

class NativeLocalRepository implements LocalSessionRepository {
  Future<Directory> _root() async {
    final path = (await _initialize())['storage_path'];
    if (path is! String || path.isEmpty) {
      throw StateError('تعذر فتح التخزين الخاص بالتطبيق');
    }
    return Directory(path).create(recursive: true);
  }

  Future<File> _file(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw ArgumentError('Invalid local session id');
    }
    return File('${(await _root()).path}/$id.json');
  }

  bool _valid(Map<String, dynamic> m, Map<String, dynamic> info) =>
      m['schema_version'] == predictionSchema &&
      m['model_version'] == info['model_version'] &&
      m['pipeline_version'] == info['pipeline_version'] &&
      m['report_schema_version'] == '1.0' &&
      m['report'] is Map &&
      m['predictions'] is Map &&
      (m['predictions'] as Map).values.every((r) =>
          r is Map &&
          validPrediction(
              Map<String, dynamic>.from(r), info['model_version'] as String));
  @override
  Future<void> save(
      Map<String, dynamic> metadata, Map<String, Uint8List> evidence) async {
    final file = await _file(metadata['id'] as String);
    final payload = utf8.encode(jsonEncode({
      ...metadata,
      'evidence': {
        for (final e in evidence.entries) e.key: base64Encode(e.value)
      }
    }));
    final files = await (await _root())
        .list()
        .where(
            (e) => e is File && e.path.endsWith('.json') && e.path != file.path)
        .cast<File>()
        .toList();
    var total = payload.length;
    for (final f in files) {
      total += await f.length();
    }
    if (files.length >= 10 || total > 128000000) {
      throw StateError(
          'التخزين المحلي ممتلئ؛ صدّر أو احذف جلسة قديمة ثم أعد الحفظ. لم تُحذف جلساتك.');
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(payload, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<List<Map<String, dynamic>>> list() async {
    final info = await _initialize(), items = <Map<String, dynamic>>[];
    await for (final file in (await _root()).list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        final m =
            Map<String, dynamic>.from(jsonDecode(await file.readAsString()));
        if (!_valid(m, info)) {
          await file.delete();
          continue;
        }
        items.add({
          'id': m['id'],
          'created_at': m['created_at'],
          'prayer': m['report']['prayer'],
          'overall_result': m['report']['overall_result'],
          'model_version': m['model_version']
        });
      } on FormatException {
        await file.delete();
      }
    }
    items.sort((a, b) =>
        (b['created_at'] as String).compareTo(a['created_at'] as String));
    return items;
  }

  @override
  Future<Map<String, dynamic>?> load(String id) async {
    final file = await _file(id);
    if (!await file.exists()) return null;
    final m = Map<String, dynamic>.from(jsonDecode(await file.readAsString()));
    if (!_valid(m, await _initialize())) {
      await file.delete();
      return null;
    }
    return m;
  }

  @override
  Future<Uint8List> evidence(String session, String evidenceId) async {
    final m = await load(session), value = m?['evidence']?[evidenceId];
    if (value is! String) {
      throw StateError('الصورة غير متاحة في التخزين المحلي');
    }
    return base64Decode(value);
  }

  @override
  Future<void> delete(String id) async {
    final file = await _file(id);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<String> export(String id) async {
    final m = await load(id);
    if (m == null) throw StateError('التقرير غير متاح');
    return exportSnapshot(m);
  }
}
