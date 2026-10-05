import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/keypoint.dart';
import '../services/pose_detector.dart';
import '../services/prayer_guidance_client.dart';
import '../prayer/prayer_definition.dart';
import '../prayer/prayer_content.dart';
import '../prayer/prayer_pose_classifier.dart';
import '../prayer/prayer_sequence_engine.dart';
import '../prayer/prayer_reference.dart';
import '../prayer/prayer_calibration.dart';
import '../prayer/prayer_floor_check.dart';

class PrayerController extends ChangeNotifier {
  PrayerController(
      {required PrayerDefinition definition,
      required this.detector,
      this.reference,
      this.guidance,
      DateTime Function()? clock})
      : engine = PrayerSequenceEngine(definition),
        calibration = reference == null ? null : PrayerCalibration(reference),
        matcher = reference == null ? null : PrayerReferenceMatcher(reference),
        sessionBegun = reference == null,
        clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final PoseDetector detector;
  final PrayerSequenceEngine engine;
  final PrayerReference? reference;
  final PrayerCalibration? calibration;
  final PrayerReferenceMatcher? matcher;
  final floorCheck = PrayerFloorCheck();
  /// Optional advisory guidance source. While null the controller performs no
  /// network I/O and station progression stays entirely local.
  final PrayerGuidanceSource? guidance;
  String? guidanceText;
  bool guidanceDegraded = false;
  bool guidancePending = false;
  String? guidanceError;
  String? _guidanceKey;
  int _guidanceRetries = 0;
  int _guidanceLowEvents = 0;
  bool sessionBegun;
  bool get calibrating => !sessionBegun && calibration != null;
  bool get canBegin =>
      started &&
      calibrating &&
      !floorCheck.active &&
      calibration!.isReady(clock());
  double get previewAspectRatio => detector is PosePreviewGeometry
      ? (detector as PosePreviewGeometry).previewAspectRatio
      : 1;
  bool get previewMirrored =>
      detector is PosePreviewGeometry &&
      (detector as PosePreviewGeometry).previewMirrored;
  final classifier = const PrayerPoseClassifier();
  StreamSubscription<List<Keypoint>>? _subscription;
  Timer? _watchdog;
  Future<void>? _stopFuture;
  Future<void>? _detectorStart;
  DateTime? _lastPose;
  bool _disposed = false, starting = false, started = false;
  String? sourceError;
  List<Keypoint> _keypoints = [];
  List<Keypoint> get keypoints => _keypoints;
  PrayerSessionState get state => engine.state;

  Future<void> start() async {
    if (starting ||
        started ||
        _disposed ||
        state.sessionStatus != SessionStatus.active) {
      return;
    }
    starting = true;
    sourceError = null;
    notifyListeners();
    _subscription = detector.stream.listen(_onPose, onError: (Object error) {
      if (_disposed) return;
      sourceError = PrayerContent.adjust;
      _onPose([]);
    });
    try {
      _detectorStart = detector.start();
      await _detectorStart;
      if (_disposed || state.sessionStatus != SessionStatus.active) {
        await detector.stop();
        return;
      }
      started = true;
      _lastPose = clock();
      _watchdog = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_disposed || state.sessionStatus != SessionStatus.active) return;
        final timeout =
            calibrating ? calibration!.maxGap : const Duration(seconds: 1);
        if (clock().difference(_lastPose!) > timeout) {
          _keypoints = [];
          if (calibrating) {
            floorCheck.observe([], previewAspectRatio, clock());
            calibration!.observe([], previewAspectRatio, clock());
          } else {
            engine.observe(
                const PoseObservation(PrayerPose.unknown, 0), clock());
          }
          notifyListeners();
        }
      });
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      sourceError =
          'تعذر بدء الكاميرا أو الفيديو. تحقق من الأذونات وحاول مجدداً.';
    } finally {
      starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _onPose(List<Keypoint> points) {
    if (_disposed || state.sessionStatus != SessionStatus.active) return;
    _lastPose = clock();
    if (points.isNotEmpty) sourceError = null;
    _keypoints = List.unmodifiable(points);
    if (calibrating) {
      if (floorCheck.active) {
        floorCheck.observe(points, previewAspectRatio, _lastPose!);
        if (!floorCheck.active) calibration!.reset();
        notifyListeners();
        return;
      }
      calibration!.observe(points, previewAspectRatio, _lastPose!);
      notifyListeners();
      return;
    }
    var observation =
        classifier.classify(points, aspectRatio: previewAspectRatio);
    final expected = state.expectedStation;
    if (matcher != null &&
        expected != null &&
        observation.pose == expected.pose) {
      final distance =
          matcher!.distance(points, expected, aspectRatio: previewAspectRatio);
      // Conservative starter tolerance, requires real-camera acceptance calibration.
      if (distance > .32 ||
          (observation.pose == PrayerPose.standing &&
              calibration!.check(points, previewAspectRatio) != null)) {
        observation = const PoseObservation(PrayerPose.unknown, 0);
      }
    }
    engine.observe(observation, _lastPose!);
    if (state.sessionStatus == SessionStatus.completed) {
      _watchdog?.cancel();
      _stopFuture ??= detector.stop();
    }
    _maybeRequestGuidance();
    notifyListeners();
  }

  bool beginPrayer() {
    if (!canBegin || _disposed || state.sessionStatus != SessionStatus.active) {
      return false;
    }
    sessionBegun = true;
    // Calibration evidence is never counted as prayer progress.
    notifyListeners();
    _guidanceRetries = 0;
    _guidanceLowEvents = 0;
    unawaited(_requestGuidance('start'));
    return true;
  }

  void startFloorCheck() {
    if (!canBegin) return;
    floorCheck.start();
    calibration!.reset();
    notifyListeners();
  }

  void finish() {
    engine.stop();
    _watchdog?.cancel();
    _stopFuture ??= detector.stop();
    unawaited(_requestGuidance('stopped'));
    notifyListeners();
  }

  /// Requests a cue only for discrete session events — never per frame.
  ///
  /// The engine already owns progression; this hook merely mirrors notable
  /// transitions so the model can phrase one short sentence.
  void _maybeRequestGuidance() {
    if (guidance == null || _disposed) return;
    final s = engine.state;
    final String event;
    if (s.sessionStatus == SessionStatus.completed) {
      event = 'completed';
    } else if (s.retryCount > _guidanceRetries) {
      event = 'retry';
    } else if (s.lowConfidenceEvents > _guidanceLowEvents) {
      event = 'uncertain';
    } else {
      return;
    }
    _guidanceRetries = s.retryCount;
    _guidanceLowEvents = s.lowConfidenceEvents;
    unawaited(_requestGuidance(event));
  }

  Future<void> _requestGuidance(String event) async {
    final source = guidance;
    if (source == null || _disposed) return;
    final s = engine.state;
    final station =
        s.expectedStation ?? s.currentStation ?? PrayerStation.standing;
    final rakahIndex =
        (s.currentRakah - 1).clamp(0, s.definition.rakahs.length - 1);
    final key = '$event|${wireStation(station)}|${s.currentRakah}';
    if (key == _guidanceKey) return;
    _guidanceKey = key;
    guidancePending = true;
    guidanceError = null;
    notifyListeners();
    try {
      final result = await source.request(PrayerGuidanceRequest(
        prayer: wirePrayer(s.prayerType),
        station: wireStation(station),
        event: event,
        rakah: s.currentRakah,
        stationIndex: s.stationIndex,
        totalStations: s.definition.rakahs[rakahIndex].stations.length,
        retries: s.retryCount,
        coreMovementsDone: s.coreMovements,
      ));
      if (_disposed) return;
      guidanceText = result?.text;
      guidanceDegraded = result?.degraded ?? false;
      // A null result means the service was unreachable; allow a later retry
      // instead of pinning the dedupe key to a failed attempt.
      if (result == null) _guidanceKey = null;
    } catch (_) {
      if (_disposed) return;
      guidanceText = null;
      guidanceDegraded = false;
      guidanceError = 'تعذر جلب الإرشاد النصي.';
      _guidanceKey = null;
    } finally {
      if (!_disposed) {
        guidancePending = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    await _subscription?.cancel();
    try {
      await _detectorStart;
    } catch (_) {
      // Startup errors are reported by start(); still release partial resources.
    }
    await _stopFuture;
    await detector.dispose();
  }
}
