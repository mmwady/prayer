import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../video/analysis_report.dart';
import '../video/video_source.dart';
import 'contracts.dart';
import 'provider.dart';
import 'report_engine.dart';
import 'assessment_options.dart';
import '../accounts/sync_adapter.dart';

/// Gallery capture is independent of report observations and religious validity.
class StableLocalCapture {
  String? candidate, lastAction;
  int count = 0, lastTime = -3000;
  bool update(Map<String, dynamic> r, int time) {
    final action =
        r['pose_detected'] == true ? r['predicted_action'] as String? : null;
    if (action == null || (r['confidence'] as num) < .7) {
      candidate = null;
      count = 0;
      return false;
    }
    if (candidate == action) {
      count++;
    } else {
      candidate = action;
      count = 1;
      if (action != lastAction) lastAction = null;
    }
    if (count >= 3 && time - lastTime >= 3000 && action != lastAction) {
      lastAction = action;
      lastTime = time;
      return true;
    }
    return false;
  }
}

class LocalSession {
  LocalSession({LocalInference? inference, LocalSessionRepository? repository})
      : inference = inference ?? createLocalInference(),
        repository = repository ?? createLocalRepository();
  final LocalInference inference;
  final LocalSessionRepository repository;
  Map<String, dynamic>? info, reportData, latest;
  String? id, prayer;
  String? _syncBinding;
  int generation = 0;
  double processingMs = 0;
  bool evidenceLimitReached = false;
  List<Map<String, dynamic>> samples = [], captures = [];
  Map<String, Uint8List> images = {};
  StableLocalCapture stable = StableLocalCapture();
  LocalAssessmentOptions options = const LocalAssessmentOptions();
  LocalAssessmentOptions _activeOptions = const LocalAssessmentOptions();
  Future<void> _operation = Future.value();
  String? _groupSignature, _bestFrame;
  int? _lastTimestamp;
  double _bestConfidence = -1;
  int _imageBytes = 0;
  Future<Map<String, dynamic>> initialize() async {
    info ??= await inference.initialize();
    return {...localConfiguration, ...info!};
  }

  Future<void> create(String p) async {
    await initialize();
    id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    prayer = p;
    _syncBinding = PrayerSyncAdapter.binding;
    _activeOptions = options;
    reportData = null;
    latest = null;
    processingMs = 0;
    samples = [];
    captures = [];
    images = {};
    _imageBytes = 0;
    evidenceLimitReached = false;
    stable = StableLocalCapture();
    _groupSignature = _bestFrame = null;
    _lastTimestamp = null;
    _bestConfidence = -1;
    generation++;
  }

  Future<void> add(SampledFrame frame, {bool live = false}) {
    final token = generation;
    final next = _operation.then((_) async {
      if (token != generation) return;
      if (samples.length >= 2400) {
        throw StateError('وصلت الجلسة إلى حد الصور المحلي');
      }
      if (samples.isNotEmpty &&
          (frame.index <= (samples.last['sequence_index'] as int) ||
              frame.timestampMs <= (samples.last['timestamp_ms'] as int))) {
        throw StateError('INVALID_TIMESTAMP_ORDER');
      }
      final value = await inference.analyze(frame.jpeg);
      if (token != generation) return;
      final r = value.result, version = info!['model_version'] as String;
      if (!validPrediction(r, version)) {
        throw StateError(
            'نتيجة محلية غير مكتملة؛ قرارات النماذج الثلاثة مطلوبة');
      }
      latest = r;
      processingMs = (r['inference_ms'] as num).toDouble();
      final frameId = 'frame_${frame.index}',
          sample = <String, dynamic>{
            'frame_id': frameId,
            'sequence_index': frame.index,
            'timestamp_ms': frame.timestampMs,
            'result': r,
            'landmarks': value.landmarks,
          };
      samples.add(sample);
      final assessed = assessLocalSample(sample, _activeOptions)['assessment']
          as Map<String, dynamic>;
      final confidence = (assessed['confidence'] as num).toDouble(),
          pose = resultPose(assessed),
          valid = r['pose_detected'] == true &&
              confidence >= .65 &&
              pose != 'unknown';
      final signature = valid ? pose : 'uncertain';
      if (signature != _groupSignature ||
          _lastTimestamp == null ||
          frame.timestampMs - _lastTimestamp! > 1000) {
        _groupSignature = signature;
        _bestFrame = null;
        _bestConfidence = -1;
      }
      _lastTimestamp = frame.timestampMs;
      final auto = live && stable.update(r, frame.timestampMs);
      if (auto) {
        captures.add({
          'frame_id': frameId,
          'timestamp_ms': frame.timestampMs,
          'result': r
        });
        if (captures.length > 12) captures.removeAt(0);
      }
      if (r['pose_detected'] == true && confidence > _bestConfidence) {
        if (_bestFrame != null &&
            !captures.any((c) => c['frame_id'] == _bestFrame)) {
          final old = images.remove(_bestFrame);
          _imageBytes -= old?.length ?? 0;
        }
        _bestFrame = frameId;
        _bestConfidence = confidence;
        final preview = await value.loadPreview();
        if (token != generation) return;
        _retain(frameId, preview ?? frame.jpeg);
      } else if (auto) {
        final preview = await value.loadPreview();
        if (token != generation) return;
        _retain(frameId, preview ?? frame.jpeg);
      }
    });
    _operation = next.catchError((Object _) {});
    return next;
  }

  void _retain(String frameId, Uint8List bytes) {
    if (images.containsKey(frameId)) return;
    if (_imageBytes + bytes.length > 64000000) {
      evidenceLimitReached = true;
      return;
    }
    images[frameId] = bytes;
    _imageBytes += bytes.length;
  }

  Future<void> complete() async {
    final token = generation;
    await _operation;
    if (token != generation) return;
    if (samples.isEmpty) throw StateError('لا توجد صور مكتملة التحليل');
    final data = await inference.report(prayer!, samples, {
      'analysis_id': id,
      ..._activeOptions.toMap(),
      'model_version': info!['model_version'],
      'sample_fps': 4
    });
    if (token != generation) return;
    data['captured_actions'] = List<Map<String, dynamic>>.from(captures);
    final missing = images.keys.toSet();
    if (data['raw_assessment'] is Map) {
      final raw = data['raw_assessment'] as Map;
      for (final item in [
        ...raw['events'] as List,
        ...raw['unexpected_movements'] as List,
        for (final row in raw['rakahs'] as List) ...row['stations'] as List,
      ]) {
        if (!missing.contains(item['evidence_id'])) item['evidence_id'] = null;
      }
    }
    for (final e in (data['events'] as List)) {
      if (e['evidence_id'] != null && !missing.contains(e['evidence_id'])) {
        e['evidence_id'] = null;
      }
    }
    for (final e in (data['unexpected_movements'] as List)) {
      if (e['evidence_id'] != null && !missing.contains(e['evidence_id'])) {
        e['evidence_id'] = null;
      }
    }
    for (final row in (data['rakahs'] as List)) {
      for (final s in row['stations'] as List) {
        if (s['evidence_id'] != null && !missing.contains(s['evidence_id'])) {
          s['evidence_id'] = null;
        }
      }
    }
    // Store only selected report/capture evidence, never the original source video.
    final needed = <String>{
      for (final e in data['events'] as List)
        if (e['evidence_id'] is String) e['evidence_id'] as String,
      if (data['raw_assessment'] is Map)
        for (final e in data['raw_assessment']['events'] as List)
          if (e['evidence_id'] is String) e['evidence_id'] as String,
      for (final c in captures) c['frame_id'] as String
    };
    final evidence = {
      for (final e in images.entries)
        if (needed.contains(e.key)) e.key: e.value
    };
    reportData = data;
    if (evidenceLimitReached) {
      data['storage_warning'] =
          'وصلت صور الأدلة إلى الحد المحلي؛ بعض الصور غير متاحة. نتائج التصنيف محفوظة دون تخمين.';
    }
    try {
      await repository.save({
        'id': id,
        'schema_version': predictionSchema,
        'report_schema_version': '1.0',
        'pipeline_version': info!['pipeline_version'] ?? 'web',
        'model_version': info!['model_version'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'report': data,
        'predictions': data['predictions']
      }, evidence);
    } catch (e) {
      data['storage_warning'] =
          'ظهر التقرير على جهازك، لكن تعذر حفظه في السجل المحلي: $e';
    }
    // Optional scalar-only post-result adapter. No inference data crosses it.
    if (data['synthetic'] != true && prayer != 'demo') {
      try {
        await PrayerSyncAdapter.completed(_syncBinding, {
          'client_attempt_id': id,
          'prayer': prayer,
          'performed_at': DateTime.now().toUtc().toIso8601String(),
          'valid': data['overall_result'] == 'OBSERVED_COMPLETE',
          'sequence_valid': data['overall_result'] == 'OBSERVED_COMPLETE',
          'uncertain': data['overall_result'] == 'REVIEW_REQUIRED',
          'rakats_expected': data['expected_rakahs'],
          'rakats_completed': data['observed_rakahs'],
          'analysis_version': info!['model_version'],
        });
      } catch (_) {
        data['storage_warning'] = 'التقرير المحلي متاح، لكن تعذر حفظ ملخص المتابعة للمزامنة.';
      }
    }
  }

  Map<String, dynamic> status() => {
        'status': reportData == null ? 'PROCESSING' : 'COMPLETED',
        'uploaded_frames': samples.length,
        'processed_frames': samples.length,
        'processing_ms': processingMs
      };
  Future<Uint8List> evidence(String e) async {
    final bytes = images[e];
    if (bytes != null) return bytes;
    if (id != null) return repository.evidence(id!, e);
    throw StateError('الصورة غير متاحة محليًا');
  }

  Future<void> discard() async {
    generation++;
    await _operation;
    id = null;
    reportData = null;
    latest = null;
    processingMs = 0;
    samples = [];
    images = {};
    captures = [];
    _imageBytes = 0;
  }

  Future<void> deleteSaved() async {
    final key = id;
    if (key != null) await repository.delete(key);
    await discard();
  }

  Future<String> export() async {
    if (id == null) throw StateError('لا يوجد تقرير');
    try {
      return await repository.export(id!);
    } catch (_) {
      if (reportData == null) rethrow;
      return exportLocalSnapshot({
        'id': id,
        'schema_version': predictionSchema,
        'report_schema_version': '1.0',
        'pipeline_version': info!['pipeline_version'],
        'model_version': info!['model_version'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'report': reportData,
        'predictions': reportData!['predictions'],
        'evidence': {
          for (final e in images.entries) e.key: base64Encode(e.value)
        }
      });
    }
  }

  void close() {
    generation++;
    unawaited(_operation.whenComplete(inference.close));
  }

  AnalysisReport get report {
    if (reportData == null) throw StateError('لم يكتمل التقرير');
    return AnalysisReport.fromJson(reportData!);
  }
}
