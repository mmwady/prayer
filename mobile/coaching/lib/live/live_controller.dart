import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../video/analysis_client.dart';
import '../video/analysis_report.dart';
import '../video/video_source.dart';
import 'camera_source.dart';
import 'live_client.dart';
import 'frame_store.dart';
import 'frame_store_provider.dart';

enum LiveMode { buffered, adaptive }

enum LivePhase {
  setup,
  starting,
  streaming,
  reconnecting,
  finishing,
  completed,
  cancelled,
  failed
}

class LiveController extends ChangeNotifier {
  LiveController(
      {required this.camera,
      required this.api,
      this.retryDelay = const Duration(seconds: 2),
      this.pollDelay = const Duration(milliseconds: 500),
      LiveFrameStore? store})
      : _customStore = store != null,
        _store = store ?? createLiveFrameStore();
  final LiveCamera camera;
  final LiveAnalysisService api;
  final Duration retryDelay;
  final Duration pollDelay;
  final bool _customStore;
  LiveFrameStore _store;
  LiveFrameStore get store => _store;
  LiveMode mode = LiveMode.buffered;
  double processingMs = 0;
  int serverPending = 0, pendingBytes = 0;
  LivePhase phase = LivePhase.setup;
  Map<String, dynamic>? config;
  AnalysisReport? report;
  String? error;
  bool awake = true, opening = false;
  bool frontCamera = true;
  int captured = 0, uploaded = 0, processed = 0, dropped = 0, elapsedMs = 0;
  int _lastTimestamp = -1;
  bool _fatalPacket = false;
  final Queue<({int index, int time, int bytes})> _queue = Queue();
  Future<void> _saving = Future.value();
  int _persisting = 0;
  bool _storageFailure = false;
  Future<void>? _sending;
  Future<void>? _opening, _starting, _finishing, _cancelling;
  bool _disposed = false, _cancelled = false, _acceptFrames = false;
  final Stopwatch _clock = Stopwatch();
  Timer? _tick;
  DateTime? _drainDeadline;
  bool get busy => [
        LivePhase.starting,
        LivePhase.streaming,
        LivePhase.reconnecting,
        LivePhase.finishing
      ].contains(phase);
  int get pending => _queue.length + _persisting;
  bool get canRetry => !_fatalPacket && !_storageFailure;
  double get effectiveFps => elapsedMs > 0 ? captured * 1000 / elapsedMs : 0;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> open() {
    if (busy || _cancelling != null) return Future.value();
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<void> switchCamera() {
    if (busy || opening || !camera.ready || _cancelling != null) {
      return Future.value();
    }
    return _opening = _switchCamera().whenComplete(() => _opening = null);
  }

  Future<void> _switchCamera() async {
    opening = true;
    error = null;
    _emit();
    try {
      await camera.open(front: !frontCamera, requireDirection: true);
      frontCamera = !frontCamera;
    } catch (e) {
      error =
          'تعذر تبديل الكاميرا: $e. يمكنك إعادة فتح الكاميرا والمحاولة مجددًا.';
    } finally {
      opening = false;
      _emit();
    }
  }

  Future<void> _open() async {
    opening = true;
    error = null;
    _emit();
    try {
      config = await api.configuration();
      if (config?['live_enabled'] != true) {
        throw StateError('المعالج الحالي لا يدعم التحليل المباشر.');
      }
      if (!(config?['live_modes'] as List? ?? []).contains('buffered')) {
        throw StateError('المعالج الحالي لا يدعم أوضاع الالتقاط.');
      }
      if (!_disposed) await camera.open(front: frontCamera);
    } catch (e) {
      error = e.toString();
    } finally {
      opening = false;
      _emit();
    }
  }

  Future<void> start(String prayer, {required bool consent, String? scenario}) {
    if (busy || opening || _cancelling != null) {
      return _starting ?? Future.value();
    }
    if ((!api.isLocal && !consent) || !camera.ready || config == null) {
      error = api.isLocal
          ? 'افتح الكاميرا وانتظر جاهزية النماذج المحلية.'
          : 'افتح الكاميرا ووافق على إرسال الصور أولًا.';
      _emit();
      return Future.value();
    }
    return _starting = _start(prayer, scenario);
  }

  Future<void> _start(String prayer, String? scenario) async {
    _cancelled = false;
    error = null;
    report = null;
    captured = uploaded = processed = dropped = elapsedMs = 0;
    _lastTimestamp = -1;
    _fatalPacket = false;
    _storageFailure = false;
    pendingBytes = serverPending = _persisting = 0;
    processingMs = 0;
    _queue.clear();
    _drainDeadline = null;
    phase = LivePhase.starting;
    _emit();
    try {
      await api.disconnect();
      await api.delete();
      if (!_customStore && api.isLocal && mode == LiveMode.adaptive) {
        await _store.clear();
        _store =
            MemoryLiveFrameStore(maxBytes: config!['max_frame_bytes'] as int);
      } else if (!_customStore && _store is MemoryLiveFrameStore) {
        await _store.clear();
        _store = createLiveFrameStore();
      }
      await store.open();
      if (_cancelled) return;
      await api.createLive(
          prayer, (config!['frame_sample_fps'] as num).toDouble(), scenario,
          mode: mode.name);
      if (_cancelled) return;
      await api.connect();
      if (_cancelled) return;
      awake = await camera.keepAwake(true);
      _acceptFrames = true;
      _clock
        ..reset()
        ..start();
      await camera.capture((config!['frame_sample_fps'] as num).toDouble(),
          config!['max_dimension'] as int, _frame, _cameraError,
          shouldCapture: _shouldCapture);
      if (_cancelled) {
        await camera.stop();
        return;
      }
      phase = LivePhase.streaming;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsedMs = _clock.elapsedMilliseconds;
        if (elapsedMs >= (config!['max_duration_ms'] as int)) {
          error = 'وصلت الجلسة إلى الحد الأقصى للمدة؛ جارٍ إعداد التقرير.';
          unawaited(finish());
        }
        _emit();
      });
      _emit();
    } catch (e) {
      if (!_cancelled) {
        error = e.toString();
        phase = LivePhase.failed;
        _acceptFrames = false;
        await camera.stop();
        await camera.keepAwake(false);
        await api.disconnect();
        // Failed starts cannot leave a camera session consuming backend capacity.
        try {
          await api.delete();
        } catch (_) {/* Retry/cancel can delete again. */}
        _emit();
      }
    }
  }

  bool _shouldCapture() {
    if (!_acceptFrames || _cancelled) return false;
    final limit = (config!['live_buffer_bytes'] as num?)?.toInt() ?? 480000000;
    if (captured >= (config!['max_frames'] as int) ||
        (captured + 1) * (config!['max_frame_bytes'] as int) > limit ||
        pendingBytes + (config!['max_frame_bytes'] as int) > limit) {
      error =
          'وصلت الجلسة إلى حد الصور أو التخزين؛ توقف الالتقاط لاستكمال الصور المحفوظة.';
      unawaited(finish());
      return false;
    }
    if (api.isLocal &&
        processingMs > 0 &&
        _clock.elapsedMilliseconds - _lastTimestamp <
            processingMs.clamp(220, 2000)) {
      return false;
    }
    return mode == LiveMode.buffered || pending == 0;
  }

  void _frame(int time, Uint8List jpeg) {
    if (!_acceptFrames || _cancelled) return;
    // Adaptive selection happens before JPEG conversion in real camera adapters.
    if (!_shouldCapture()) return;
    if (time >= (config!['max_duration_ms'] as int)) {
      unawaited(finish());
      return;
    }
    _lastTimestamp = time;
    final index = captured++;
    if (jpeg.length > (config!['max_frame_bytes'] as int)) {
      _cameraError(const AnalysisApiError('FRAME_TOO_LARGE'));
      return;
    }
    _persisting++;
    pendingBytes += jpeg.length;
    _saving = _saving.then((_) async {
      try {
        if (_cancelled) return;
        await store.put(index, jpeg);
        if (_cancelled) return;
        _queue.add((index: index, time: time, bytes: jpeg.length));
        if (phase != LivePhase.failed) _pump();
      } catch (e) {
        _localStorageError(e);
      } finally {
        _persisting--;
        _emit();
      }
    });
    _emit();
  }

  void _localStorageError(Object e) {
    _storageFailure = true;
    error =
        'توقف الالتقاط لتعذر حفظ صورة أو قراءتها على الجهاز: $e. الصور المحفوظة لم تُحذف. ألغِ الجلسة وأعد المحاولة بعد توفير مساحة التخزين.';
    phase = LivePhase.failed;
    _acceptFrames = false;
    _tick?.cancel();
    unawaited(camera.stop());
    unawaited(camera.keepAwake(false));
    _emit();
  }

  void _pump() {
    _sending ??= _send().whenComplete(() {
      _sending = null;
      if (_queue.isNotEmpty && !_cancelled && phase != LivePhase.failed) {
        _pump();
      }
    });
  }

  Future<void> _send() async {
    while (_queue.isNotEmpty && !_cancelled) {
      final frame = _queue.first;
      Uint8List jpeg;
      try {
        jpeg = await store.read(frame.index);
      } catch (e) {
        _localStorageError(e);
        return;
      }
      try {
        final ack =
            await api.sendFrame(SampledFrame(frame.index, frame.time, jpeg));
        if (_cancelled) return;
        await store.remove(frame.index);
        _queue.removeFirst();
        pendingBytes -= frame.bytes;
        uploaded = ack['uploaded_frames'] as int;
        processed = ack['processed_frames'] as int;
        serverPending = uploaded - processed;
        processingMs = (ack['processing_ms'] as num?)?.toDouble() ?? 0;
        if (phase == LivePhase.reconnecting) phase = LivePhase.streaming;
        _emit();
      } catch (e) {
        if (_cancelled) return;
        if (api.isLocal ||
            e is AnalysisApiError ||
            (_drainDeadline != null &&
                DateTime.now().isAfter(_drainDeadline!))) {
          error = '$e';
          _fatalPacket = e is AnalysisApiError;
          phase = LivePhase.failed;
          _acceptFrames = false;
          _tick?.cancel();
          await camera.stop();
          await camera.keepAwake(false);
          _emit();
          return;
        }
        if (phase != LivePhase.finishing) phase = LivePhase.reconnecting;
        _emit();
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  void _cameraError(Object e) {
    if (!_acceptFrames) return;
    error = 'توقف التقاط الكاميرا: $e. سيصدر التقرير للصور المرصودة فقط.';
    unawaited(finish());
  }

  Future<void> finish() {
    if (_finishing != null) return _finishing!;
    if (!busy && phase != LivePhase.failed) return Future.value();
    if (api.jobId == null) return Future.value();
    return _finishing = _finish().whenComplete(() => _finishing = null);
  }

  Future<void> _finish() async {
    if (_fatalPacket || _storageFailure) {
      error ??=
          'تعذر استكمال كل الصور؛ لم تُحذف الصور المعلقة. يمكنك إلغاء الجلسة وحذف البيانات.';
      _emit();
      return;
    }
    _acceptFrames = false;
    phase = LivePhase.finishing;
    _tick?.cancel();
    _clock.stop();
    elapsedMs = _clock.elapsedMilliseconds;
    _emit();
    _drainDeadline = DateTime.now().add(const Duration(minutes: 2));
    try {
      await camera.stop();
      await camera.keepAwake(false);
      await _saving;
      if (_storageFailure) return;
      if (_sending == null && _queue.isNotEmpty) _pump();
      await _sending;
      if (_cancelled || phase == LivePhase.failed) return;
      if (uploaded == 0) throw StateError('لا توجد صور مكتملة التحليل.');
      await api.disconnect();
      final duration =
          elapsedMs > _lastTimestamp ? elapsedMs : _lastTimestamp + 1;
      var state = await api
          .finishLive(duration.clamp(1, config!['max_duration_ms'] as int));
      while (!_cancelled &&
          state['status'] != null &&
          state['status'] != 'COMPLETED') {
        if (state['status'] == 'FAILED' || state['status'] == 'CANCELLED') {
          throw AnalysisApiError(
              state['error']?.toString() ?? 'ANALYSIS_PROCESSING_FAILED');
        }
        uploaded = state['uploaded_frames'] as int;
        processed = state['processed_frames'] as int;
        serverPending = uploaded - processed;
        _emit();
        await Future<void>.delayed(pollDelay);
        if (!_cancelled) state = await api.status();
      }
      if (_cancelled) return;
      processed = (state['processed_frames'] as int?) ?? processed;
      serverPending = uploaded - processed;
      report = await api.report();
      if (!_cancelled) phase = LivePhase.completed;
      await camera.close();
    } catch (e) {
      if (!_cancelled) {
        error = '$e';
        phase = LivePhase.failed;
      }
    } finally {
      _emit();
    }
  }

  Future<void> cancel() =>
      _cancelling ??= _cancel().whenComplete(() => _cancelling = null);
  Future<void> _cancel() async {
    _cancelled = true;
    _acceptFrames = false;
    phase = LivePhase.cancelled;
    _tick?.cancel();
    _clock.stop();
    _emit();
    await _opening;
    await _starting;
    await camera.close();
    await camera.keepAwake(false);
    await api.disconnect();
    await _saving;
    await _sending;
    await _finishing;
    _queue.clear();
    pendingBytes = 0;
    await store.clear();
    try {
      await api.delete();
    } catch (e) {
      error = 'تعذر حذف بيانات الجلسة: $e';
    }
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel().whenComplete(api.close));
    super.dispose();
  }
}
