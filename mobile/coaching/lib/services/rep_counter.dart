import 'dart:collection';
import 'dart:math' as math;

import '../models/keypoint.dart';

/// Abstract strategy class for sequence-based rep counting.
abstract class SequenceRepCounter {
  /// Evaluates the incoming frame in the context of the running sequence.
  /// Returns `true` if a completed repetition is detected.
  bool checkRepPattern(List<Keypoint> currentFrame);

  /// Drops any in-progress repetition state.
  ///
  /// Controllers call this when form analysis detects an invalid variant so a
  /// bad movement cannot later complete and increment the valid-rep counter.
  void reset() {}
}

/// Hybrid repetition counter.
///
/// The original implementation used only DTW over a long sliding window. That
/// works when the template is a long recorded sequence, but it becomes too strict
/// for short synthetic demo templates such as push-up side-left/side-right.
///
/// This class now keeps DTW for long templates and automatically switches to a
/// phase-based counter for short templates. The phase counter is intentionally
/// conservative: it counts only after it sees a clear down phase followed by a
/// return to the top phase.
class DtwRepCounter implements SequenceRepCounter {
  DtwRepCounter({
    required this.templateSequence,
    this.windowSize = 60,
    this.similarityThreshold = 0.70,
  });

  /// The pre-recorded perfect repetition to compare against.
  final List<List<Keypoint>> templateSequence;

  final int windowSize;
  final double similarityThreshold;
  final Queue<List<Keypoint>> _slidingWindow = Queue<List<Keypoint>>();

  // ── Phase-based fallback state ─────────────────────────────────────────
  double? _smoothedDepth;
  double? _topDepth;
  double? _bottomDepth;
  bool _sawBottom = false;
  int _bottomFrames = 0;
  int _topFrames = 0;
  int _cooldownFrames = 0;

  /// Short templates are usually synthetic phase templates, not dense recorded
  /// sequences. DTW can be too strict there, so use the phase counter instead.
  bool get _usePhaseCounter => templateSequence.length < 20;

  @override
  void reset() {
    _slidingWindow.clear();
    _smoothedDepth = null;
    _topDepth = null;
    _bottomDepth = null;
    _sawBottom = false;
    _bottomFrames = 0;
    _topFrames = 0;
    _cooldownFrames = 0;
  }

  @override
  bool checkRepPattern(List<Keypoint> currentFrame) {
    if (_usePhaseCounter) {
      return _checkPhaseBasedRep(currentFrame);
    }

    _slidingWindow.addLast(currentFrame);

    if (_slidingWindow.length < windowSize) {
      return false;
    }

    if (_slidingWindow.length > windowSize) {
      _slidingWindow.removeFirst();
    }

    final similarity = _calculateDtwSimilarity(_slidingWindow.toList());

    if (similarity > similarityThreshold) {
      _slidingWindow.clear();
      return true;
    }

    return false;
  }

  /// Counts push-up-like repetitions from movement phases instead of exact
  /// template-frame matching.
  ///
  /// It uses shoulder vertical movement relative to the camera frame. During a
  /// push-up, the shoulder line moves down toward the floor and then back up.
  /// We do not count until the user has visited the bottom zone and returned to
  /// the top zone for a couple of stable frames.
  bool _checkPhaseBasedRep(List<Keypoint> frame) {
    final depth = _shoulderDepth(frame);
    if (depth == null) return false;

    _smoothedDepth = _smoothedDepth == null
        ? depth
        : (_smoothedDepth! * 0.75) + (depth * 0.25);
    final currentDepth = _smoothedDepth!;

    _topDepth = _topDepth == null
        ? currentDepth
        : math.min(_topDepth!, currentDepth);
    _bottomDepth = _bottomDepth == null
        ? currentDepth
        : math.max(_bottomDepth!, currentDepth);

    final range = _bottomDepth! - _topDepth!;

    // The user has not moved enough yet. This avoids counting camera jitter,
    // breathing, or small body shifts as reps.
    if (range < 0.045) {
      return false;
    }

    final topThreshold = _topDepth! + (range * 0.35);
    final bottomThreshold = _topDepth! + (range * 0.65);

    if (_cooldownFrames > 0) {
      _cooldownFrames -= 1;
    }

    if (currentDepth >= bottomThreshold) {
      _bottomFrames += 1;
      _topFrames = 0;
    } else if (currentDepth <= topThreshold) {
      _topFrames += 1;
    } else {
      // Middle zone: do not reset aggressively. Some users pause mid-rep.
      _topFrames = 0;
    }

    if (_bottomFrames >= 2) {
      _sawBottom = true;
    }

    if (_sawBottom && _topFrames >= 2 && _cooldownFrames == 0) {
      _sawBottom = false;
      _bottomFrames = 0;
      _topFrames = 0;
      _cooldownFrames = 10;

      // Slowly re-open the range after each counted rep so the counter adapts
      // if the user changes distance from the camera during the set.
      final center = (_topDepth! + _bottomDepth!) / 2.0;
      final halfRange = math.max(range * 0.45, 0.03);
      _topDepth = center - halfRange;
      _bottomDepth = center + halfRange;

      return true;
    }

    return false;
  }

  double? _shoulderDepth(List<Keypoint> frame) {
    final points = <KeypointId, Keypoint>{for (final point in frame) point.id: point};
    final shoulders = <Keypoint>[];

    final leftShoulder = points[KeypointId.leftShoulder];
    final rightShoulder = points[KeypointId.rightShoulder];
    final leftWrist = points[KeypointId.leftWrist];
    final rightWrist = points[KeypointId.rightWrist];

    if (leftShoulder != null && leftShoulder.confidence > 0.35) {
      shoulders.add(leftShoulder);
    }
    if (rightShoulder != null && rightShoulder.confidence > 0.35) {
      shoulders.add(rightShoulder);
    }

    // Require hands to be at least partially visible. Otherwise a standing or
    // cropped pose could accidentally look like vertical push-up movement.
    final visibleHands = [leftWrist, rightWrist]
        .where((point) => point != null && point.confidence > 0.30)
        .length;

    if (shoulders.isEmpty || visibleHands == 0) {
      return null;
    }

    final shoulderY = shoulders.map((point) => point.y).reduce((a, b) => a + b) /
        shoulders.length;

    return shoulderY;
  }

  /// Calculates the Euclidean distance between two individual frames.
  double _frameDistance(List<Keypoint> frameA, List<Keypoint> frameB) {
    final normalizedA = _normalizeFrame(frameA);
    final normalizedB = _normalizeFrame(frameB);

    double totalDistance = 0.0;
    double totalWeight = 0.0;
    int commonJoints = 0;

    if (normalizedA.isEmpty || normalizedB.isEmpty) return 1000.0;

    for (final entry in normalizedA.entries) {
      final pointB = normalizedB[entry.key];
      if (pointB == null) continue;

      final pointA = entry.value;
      final weight = _jointWeight(entry.key);
      final dx = pointA.x - pointB.x;
      final dy = pointA.y - pointB.y;

      totalDistance += (dx * dx + dy * dy) * weight;
      totalWeight += weight;
      commonJoints++;
    }

    return commonJoints >= 5 && totalWeight > 0.0
        ? math.sqrt(totalDistance / totalWeight)
        : 1000.0;
  }

  /// Core Dynamic Time Warping (DTW) algorithm.
  double _calculateDtwSimilarity(List<List<Keypoint>> currentWindow) {
    final n = currentWindow.length;
    final m = templateSequence.length;

    if (n == 0 || m == 0) return 0.0;

    final dp = List.generate(
      n + 1,
      (_) => List.filled(m + 1, double.infinity),
    );

    dp[0][0] = 0.0;

    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        final cost = _frameDistance(currentWindow[i - 1], templateSequence[j - 1]);
        final minPrev = math.min(
          dp[i - 1][j - 1],
          math.min(dp[i - 1][j], dp[i][j - 1]),
        );
        dp[i][j] = cost + minPrev;
      }
    }

    final totalDistance = dp[n][m];
    final normalizedDistance = totalDistance / (n + m);
    return math.exp(-5.0 * normalizedDistance);
  }

  Map<KeypointId, _NormalizedPoint> _normalizeFrame(List<Keypoint> frame) {
    final points = <KeypointId, _NormalizedPoint>{};

    for (final keypoint in frame) {
      if (keypoint.confidence <= 0.45) continue;
      points[keypoint.id] = _NormalizedPoint(
        x: keypoint.x,
        y: keypoint.y,
        confidence: keypoint.confidence,
      );
    }

    if (points.length < 5) return const {};

    final center = _estimateBodyCenter(points);
    final scale = _estimateBodyScale(points);

    if (scale <= 1e-6 || scale.isNaN || scale.isInfinite) {
      return const {};
    }

    final normalized = <KeypointId, _NormalizedPoint>{};
    for (final entry in points.entries) {
      normalized[entry.key] = _NormalizedPoint(
        x: (entry.value.x - center.x) / scale,
        y: (entry.value.y - center.y) / scale,
        confidence: entry.value.confidence,
      );
    }

    return _rotateToUpright(normalized);
  }

  _NormalizedPoint _estimateBodyCenter(Map<KeypointId, _NormalizedPoint> points) {
    final leftHip = points[KeypointId.leftHip];
    final rightHip = points[KeypointId.rightHip];
    final spineMid = points[KeypointId.spineMid];

    if (leftHip != null && rightHip != null) {
      return _midpoint(leftHip, rightHip);
    }

    if (spineMid != null) return spineMid;

    double x = 0.0;
    double y = 0.0;
    for (final point in points.values) {
      x += point.x;
      y += point.y;
    }

    return _NormalizedPoint(
      x: x / points.length,
      y: y / points.length,
      confidence: 1.0,
    );
  }

  double _estimateBodyScale(Map<KeypointId, _NormalizedPoint> points) {
    final leftShoulder = points[KeypointId.leftShoulder];
    final rightShoulder = points[KeypointId.rightShoulder];
    final leftHip = points[KeypointId.leftHip];
    final rightHip = points[KeypointId.rightHip];

    final candidates = <double>[];

    if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null) {
      candidates.add(
        _distance(
              _midpoint(leftShoulder, rightShoulder),
              _midpoint(leftHip, rightHip),
            ) *
            2.2,
      );
    }

    if (leftShoulder != null && rightShoulder != null) {
      candidates.add(_distance(leftShoulder, rightShoulder) * 2.5);
    }

    if (leftHip != null && rightHip != null) {
      candidates.add(_distance(leftHip, rightHip) * 3.2);
    }

    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final point in points.values) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }

    final bboxDiagonal = math.sqrt(
      math.pow(maxX - minX, 2).toDouble() +
          math.pow(maxY - minY, 2).toDouble(),
    );

    if (bboxDiagonal > 0.0) candidates.add(bboxDiagonal);

    if (candidates.isEmpty) return 1.0;

    candidates.sort();
    return candidates[candidates.length ~/ 2];
  }

  Map<KeypointId, _NormalizedPoint> _rotateToUpright(
    Map<KeypointId, _NormalizedPoint> points,
  ) {
    final leftShoulder = points[KeypointId.leftShoulder];
    final rightShoulder = points[KeypointId.rightShoulder];
    final leftHip = points[KeypointId.leftHip];
    final rightHip = points[KeypointId.rightHip];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return points;
    }

    final shoulderCenter = _midpoint(leftShoulder, rightShoulder);
    final hipCenter = _midpoint(leftHip, rightHip);
    final vx = shoulderCenter.x - hipCenter.x;
    final vy = shoulderCenter.y - hipCenter.y;

    if ((vx * vx + vy * vy) < 1e-8) return points;

    final angle = (-math.pi / 2.0) - math.atan2(vy, vx);
    if (angle.abs() < 1e-6) return points;

    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final rotated = <KeypointId, _NormalizedPoint>{};

    for (final entry in points.entries) {
      final x = entry.value.x;
      final y = entry.value.y;
      rotated[entry.key] = _NormalizedPoint(
        x: (x * cosA) - (y * sinA),
        y: (x * sinA) + (y * cosA),
        confidence: entry.value.confidence,
      );
    }

    return rotated;
  }

  double _jointWeight(KeypointId id) {
    switch (id) {
      case KeypointId.spineMid:
        return 2.4;
      case KeypointId.leftHip:
      case KeypointId.rightHip:
        return 2.0;
      case KeypointId.leftElbow:
      case KeypointId.rightElbow:
      case KeypointId.leftWrist:
      case KeypointId.rightWrist:
        return 1.8;
      case KeypointId.leftShoulder:
      case KeypointId.rightShoulder:
        return 1.4;
      default:
        return 0.6;
    }
  }

  _NormalizedPoint _midpoint(_NormalizedPoint a, _NormalizedPoint b) {
    return _NormalizedPoint(
      x: (a.x + b.x) / 2.0,
      y: (a.y + b.y) / 2.0,
      confidence: math.min(a.confidence, b.confidence),
    );
  }

  double _distance(_NormalizedPoint a, _NormalizedPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt((dx * dx) + (dy * dy));
  }
}

class _NormalizedPoint {
  const _NormalizedPoint({
    required this.x,
    required this.y,
    required this.confidence,
  });

  final double x;
  final double y;
  final double confidence;
}
