import 'dart:collection';
import 'dart:math' as math;
import '../models/keypoint.dart';

/// Abstract strategy class for sequence-based rep counting.
/// Adopts the Strategy Pattern to allow different recognition architectures
/// (e.g., Dynamic Time Warping, TFLite sequence matching) to be swapped cleanly.
abstract class SequenceRepCounter {
  /// Evaluates the incoming frame in the context of the running sequence.
  /// Returns `true` if a completed repetition is detected.
  bool checkRepPattern(List<Keypoint> currentFrame);
}

/// A concrete implementation of [SequenceRepCounter] using a sliding window
/// and a (placeholder) Dynamic Time Warping (DTW) calculation.
///
/// DTW is suited for Action Recognition because it can align and compare
/// temporal sequences of varying speeds (useful for slow vs fast repetitions),
/// eliminating the need for hardcoded angle-based heuristic if/else statements.
class DtwRepCounter implements SequenceRepCounter {
  DtwRepCounter({
    required this.templateSequence,
    this.windowSize = 60,
    this.similarityThreshold = 0.70,
  });

  /// The pre-recorded perfect repetition to compare against.
  /// You can record this once by logging the frames of a good squat,
  /// then saving it as a JSON asset.
  final List<List<Keypoint>> templateSequence;

  final int windowSize;
  final double similarityThreshold;
  final Queue<List<Keypoint>> _slidingWindow = Queue<List<Keypoint>>();

  @override
  bool checkRepPattern(List<Keypoint> currentFrame) {
    // 1. Maintain the sliding window buffer
    _slidingWindow.addLast(currentFrame);

    // Allow the buffer to fill up before we start processing similarities.
    if (_slidingWindow.length < windowSize) {
      return false;
    }

    // Ensure we exactly maintain `windowSize` elements by popping the oldest frame.
    if (_slidingWindow.length > windowSize) {
      _slidingWindow.removeFirst();
    }

    // Calculate the DTW similarity between the current window and the template.
    final double similarity = _calculateDtwSimilarity(_slidingWindow.toList());

    // 3. Complete the repetition
    // If the similarity exceeds a high confidence threshold, confirm the rep.
    if (similarity > similarityThreshold) {
      // Clear the buffer entirely to prevent the current sequence overlapping
      // and double-counting the same repetition.
      _slidingWindow.clear();
      return true;
    }

    return false;
  }

  /// Calculates the Euclidean distance between two individual frames.
  ///
  /// It pairs joints by their ID and calculates the physical distance
  /// between them in the normalized coordinate space.
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

    // Return average normalized skeleton distance per joint.
    // If no joints match, return a heavy penalty (1000.0).
    return commonJoints >= 5 && totalWeight > 0.0
        ? math.sqrt(totalDistance / totalWeight)
        : 1000.0;
  }

  /// Core Dynamic Time Warping (DTW) algorithm.
  ///
  /// Finds the optimal alignment between two temporal sequences of varying speeds.
  /// Returns a similarity score between 0.0 (completely different) and 1.0 (identical).
  double _calculateDtwSimilarity(List<List<Keypoint>> currentWindow) {
    final n = currentWindow.length;
    final m = templateSequence.length;

    // Handle edge cases where templates might be missing
    if (n == 0 || m == 0) return 0.0;

    // 1. Initialize a 2D DP (Dynamic Programming) matrix with infinity.
    // dp[i][j] represents the minimum cost to align the first i frames of the
    // current window with the first j frames of the template.
    List<List<double>> dp = List.generate(
      n + 1,
      (_) => List.filled(m + 1, double.infinity),
    );

    // Base case: 0 distance for two empty sequences.
    dp[0][0] = 0.0;

    // 2. Fill the DP matrix
    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        // Calculate the spatial distance between the two specific frames
        final cost =
            _frameDistance(currentWindow[i - 1], templateSequence[j - 1]);

        // Core DTW equation: current cost + min of the three adjacent previous states
        // (representing a match, an insertion, or a deletion in time).
        final minPrev = math.min(
          dp[i - 1][j - 1], // Match (diagonal)
          math.min(
            dp[i - 1][j], // Insertion (vertical)
            dp[i][j - 1], // Deletion (horizontal)
          ),
        );
        dp[i][j] = cost + minPrev;
      }
    }

    // 3. The final element contains the total accumulated DTW distance.
    final totalDistance = dp[n][m];

    // 4. Normalize the distance by the length of the path (n + m) to prevent
    // longer sequences from having artificially high distances.
    final normalizedDistance = totalDistance / (n + m);

    // 5. Convert distance to a similarity score [0, 1] using exponential decay.
    // The constant '5.0' dictates how strictly we penalize distance; it can be
    // tuned based on real-world testing.
    final similarity = math.exp(-5.0 * normalizedDistance);

    return similarity;
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
        _distance(_midpoint(leftShoulder, rightShoulder),
                _midpoint(leftHip, rightHip)) *
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
