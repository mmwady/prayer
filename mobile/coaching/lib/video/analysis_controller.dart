import 'dart:async';
import 'package:flutter/foundation.dart';
import 'analysis_client.dart';
import 'analysis_report.dart';
import 'video_source.dart';

enum AnalysisPhase {
  selection,
  preparing,
  uploading,
  processing,
  completed,
  failed,
  cancelled
}

class AnalysisController extends ChangeNotifier {
  AnalysisController(
      {required this.source,
      required this.api,
      this.pollInterval = const Duration(seconds: 1)});
  final VideoSource source;
  final AnalysisService api;
  final Duration pollInterval;
  LocalVideo? video;
  AnalysisReport? report;
  Map<String, dynamic>? config;
  AnalysisPhase phase = AnalysisPhase.selection;
  String? error;
  int prepared = 0, uploaded = 0, total = 0, processed = 0;
  bool _cancelled = false, _disposed = false, _running = false;
  Future<void>? _operation;
  bool get busy => _running;
  bool preparingModels = false;
  Future<void>? _preparation;
  Timer? _progressTimer;
  Map<String, dynamic> get modelProgress => api is AnalysisPreparationProgress
      ? (api as AnalysisPreparationProgress).initializationProgress
      : const {};
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> select() async {
    if (_running) return;
    try {
      error = null;
      final picked = await source.pick();
      if (picked == null) return;
      video = picked;
      phase = AnalysisPhase.selection;
      _emit();
      // Opening a local file must not wait for model downloads.
      if (api.isLocal) {
        unawaited(prepareModels());
      } else {
        await prepareModels();
      }
    } catch (e) {
      error = api.isLocal
          ? 'تعذر فتح الفيديو أو تهيئة النماذج المحلية: $e'
          : 'تعذر فتح الفيديو أو الاتصال بالخادم: $e';
    }
    _emit();
  }

  Future<void> prepareModels() {
    if (config != null) return Future.value();
    return _preparation ??= _prepareModels();
  }

  Future<void> _prepareModels() async {
    preparingModels = true;
    error = null;
    _emit();
    final timer = _progressTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) => _emit());
    try {
      config = await api.configuration();
    } catch (e) {
      error = api.isLocal
          ? 'تعذر تجهيز النماذج المحلية. تحقق من الاتصال وأعد المحاولة: $e'
          : 'تعذر الاتصال بالخادم: $e';
    } finally {
      timer.cancel();
      preparingModels = false;
      _preparation = null;
      _emit();
    }
  }

  Future<void> start(String prayer, {required bool consent, String? scenario}) {
    if (_running) return _operation ?? Future.value();
    if ((!api.isLocal && !consent) || video == null || config == null) {
      error = api.isLocal
          ? 'اختر فيديو وانتظر جاهزية النماذج المحلية.'
          : 'اختر فيديو ووافق صراحةً على رفع الإطارات أولًا.';
      _emit();
      return Future.value();
    }
    _running = true;
    _operation = _run(prayer, scenario);
    return _operation!;
  }

  Future<void> _run(String prayer, String? scenario) async {
    _cancelled = false;
    error = null;
    report = null;
    prepared = uploaded = processed = 0;
    phase = AnalysisPhase.preparing;
    _emit();
    try {
      final c = config!;
      final fps = (c['frame_sample_fps'] as num).toDouble();
      final interval = (1000 / fps).round();
      total = (video!.durationMs / interval).ceil();
      if (video!.durationMs > (c['max_duration_ms'] as int) ||
          total > (c['max_frames'] as int)) {
        throw const AnalysisApiError('VIDEO_TOO_LONG');
      }
      // A retry creates a fresh job, cleaning up any previous failed attempt.
      await api.delete();
      if (_cancelled) return;
      await api.create(prayer, video!, fps, scenario);
      if (_cancelled) {
        await api.delete();
        return;
      }
      var batchIndex = 0;
      final batch = <SampledFrame>[];
      for (var i = 0; i < total; i++) {
        if (_cancelled) return;
        phase = AnalysisPhase.preparing;
        _emit();
        final frame =
            await source.frame(i, i * interval, c['max_dimension'] as int);
        if (_cancelled) return;
        if (frame.jpeg.length > (c['max_frame_bytes'] as int)) {
          throw const AnalysisApiError('FRAME_TOO_LARGE');
        }
        batch.add(frame);
        prepared++;
        if (batch.length == c['batch_frames'] || i == total - 1) {
          phase = AnalysisPhase.uploading;
          _emit();
          await api.upload(batchIndex++, batch);
          uploaded += batch.length;
          batch.clear();
          _emit();
        }
      }
      if (_cancelled) return;
      await api.complete();
      phase = AnalysisPhase.processing;
      _emit();
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      while (!_cancelled) {
        final status = await api.status();
        if (_cancelled) return;
        processed = status['processed_frames'] as int;
        _emit();
        if (status['status'] == 'COMPLETED') {
          report = await api.report();
          if (!_cancelled) phase = AnalysisPhase.completed;
          break;
        }
        if (['FAILED', 'CANCELLED'].contains(status['status'])) {
          throw AnalysisApiError(
              status['error']?.toString() ?? 'ANALYSIS_CANCELLED');
        }
        if (DateTime.now().isAfter(deadline)) {
          throw const AnalysisApiError('ANALYSIS_TIMEOUT');
        }
        await Future<void>.delayed(pollInterval);
      }
    } catch (e) {
      if (!_cancelled) {
        error = e.toString();
        phase = AnalysisPhase.failed;
      }
    } finally {
      if (_cancelled) {
        try {
          await api.delete();
        } catch (e) {
          error = 'تعذر حذف بيانات الجلسة: $e';
        }
      }
      _running = false;
      _emit();
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    phase = AnalysisPhase.cancelled;
    _emit();
    try {
      await api.delete();
    } catch (e) {
      error = 'تعذر حذف بيانات الجلسة: $e';
      _emit();
    }
    // Keep the selected decoder alive until an in-flight frame has finished.
    await _operation;
  }

  Future<void> _release() async {
    await cancel();
    await source.close();
    api.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    unawaited(_release());
    super.dispose();
  }
}
