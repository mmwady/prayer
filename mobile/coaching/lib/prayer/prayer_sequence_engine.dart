import 'prayer_definition.dart';

enum SessionStatus { active, completed, stopped }

enum MovementFeedback {
  waiting,
  completed,
  lowConfidence,
  skipped,
  repeated,
  unexpected
}

class PoseObservation {
  const PoseObservation(this.pose, this.confidence);
  final PrayerPose pose;
  final double confidence;
}

class CompletedStation {
  const CompletedStation(this.rakah, this.station);
  final int rakah;
  final PrayerStation station;
}

/// Read-only snapshot for UI and local summary. No religious assessments.
class PrayerSessionState {
  const PrayerSessionState({
    required this.definition,
    required this.currentRakah,
    required this.stationIndex,
    required this.currentStation,
    required this.observedPose,
    required this.previousPose,
    required this.confidence,
    required this.completedStations,
    required this.retryCount,
    required this.lowConfidenceEvents,
    required this.sessionStatus,
    required this.feedback,
  });
  final PrayerDefinition definition;
  PrayerType get prayerType => definition.prayerType;
  int get totalRakahs => definition.rakahCount;
  final int currentRakah;
  final int stationIndex;
  final PrayerStation? currentStation;
  PrayerStation? get expectedStation => sessionStatus == SessionStatus.active
      ? definition.rakahs[currentRakah - 1].stations[stationIndex]
      : null;
  final PrayerPose observedPose;
  final PrayerPose previousPose;
  final double confidence;
  final List<CompletedStation> completedStations;
  final int retryCount;
  final int lowConfidenceEvents;
  final SessionStatus sessionStatus;
  final MovementFeedback feedback;
  int get coreMovements =>
      completedStations.where((s) => s.station.isCore).length;
  int get additionalSittings => completedStations.length - coreMovements;
  int get completedRakahs =>
      sessionStatus == SessionStatus.completed ? totalRakahs : currentRakah - 1;
}

class PrayerSequenceEngine {
  PrayerSequenceEngine(
    this.definition, {
    this.confidenceThreshold = 0.65,
    this.stableFrames = 4,
    this.persistence = const Duration(milliseconds: 500),
    this.maxFrameGap = const Duration(milliseconds: 400),
  });

  final PrayerDefinition definition;
  final double confidenceThreshold;
  final int stableFrames;
  final Duration persistence;
  final Duration maxFrameGap;
  int _rakah = 1, _stationIndex = 0, _frames = 0, _retries = 0, _lowEvents = 0;
  PrayerPose _observed = PrayerPose.unknown, _previous = PrayerPose.unknown;
  PrayerPose? _candidate, _lastHandled;
  PrayerStation? _current;
  DateTime? _since, _lastFrame;
  double _confidence = 0;
  bool _lowEpisode = false;
  final List<CompletedStation> _completed = [];
  SessionStatus _status = SessionStatus.active;
  MovementFeedback _feedback = MovementFeedback.waiting;

  PrayerSessionState get state => PrayerSessionState(
        definition: definition,
        currentRakah: _rakah,
        stationIndex: _stationIndex,
        currentStation: _current,
        observedPose: _observed,
        previousPose: _previous,
        confidence: _confidence,
        completedStations: List.unmodifiable(_completed),
        retryCount: _retries,
        lowConfidenceEvents: _lowEvents,
        sessionStatus: _status,
        feedback: _feedback,
      );

  void stop() {
    if (_status == SessionStatus.active) _status = SessionStatus.stopped;
  }

  void observe(PoseObservation observation, DateTime now) {
    if (_status != SessionStatus.active) return;
    if (_lastFrame != null && !now.isAfter(_lastFrame!)) return;
    if (_lastFrame != null && now.difference(_lastFrame!) > maxFrameGap) {
      _candidate = null;
      _frames = 0;
    }
    _lastFrame = now;
    _previous = _observed;
    _observed = observation.pose;
    _confidence = observation.confidence.isFinite ? observation.confidence : 0;
    if (_observed == PrayerPose.unknown ||
        _confidence < confidenceThreshold ||
        _confidence > 1) {
      _candidate = null;
      _frames = 0;
      if (!_lowEpisode) {
        _lowEvents++;
        _lowEpisode = true;
      }
      _feedback = MovementFeedback.lowConfidence;
      return;
    }
    if (_candidate != _observed) {
      _candidate = _observed;
      _since = now;
      _frames = 0;
    }
    _frames++;
    if (_frames < stableFrames || now.difference(_since!) < persistence) return;
    _lowEpisode = false;
    if (_lastHandled == _observed) {
      if (_feedback == MovementFeedback.lowConfidence)
        _feedback = MovementFeedback.waiting;
      return; // A held posture is not a new movement.
    }
    _lastHandled = _observed;
    final stations = definition.rakahs[_rakah - 1].stations;
    final expected = stations[_stationIndex];
    if (_observed != expected.pose) {
      _retries++;
      final seenBefore = _completed
          .any((s) => s.rakah == _rakah && s.station.pose == _observed);
      final seenLater =
          stations.skip(_stationIndex + 1).any((s) => s.pose == _observed);
      _feedback = seenLater
          ? MovementFeedback.skipped
          : seenBefore
              ? MovementFeedback.repeated
              : MovementFeedback.unexpected;
      return;
    }
    _completed.add(CompletedStation(_rakah, expected));
    _current = expected;
    _feedback = MovementFeedback.completed;
    _stationIndex++;
    if (_stationIndex == stations.length) {
      if (_rakah == definition.rakahCount) {
        _status = SessionStatus.completed;
      } else {
        _rakah++;
        _stationIndex = 0;
      }
    }
  }
}
