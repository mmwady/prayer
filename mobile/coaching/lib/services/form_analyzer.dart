// ─────────────────────────────────────────────────────────────────────────────
// form_analyzer.dart
//
// Robust Dynamic Form Analyzer using Template Matching.
//
// Improvements over the simple x/y comparison version:
// 1. Body-centered normalization: removes camera distance and body position noise.
// 2. Optional mirror handling: tolerates front-camera mirroring / left-right flips.
// 3. Angle comparison: compares movement mechanics, not only joint coordinates.
// 4. Temporal confirmation: avoids false positives from one noisy frame.
// 5. Match-quality gate: ignores unstable/out-of-frame poses instead of guessing.
//
// The camera feed stays on-device. This analyzer only emits a PoseEvent when a
// meaningful and stable form deviation is detected.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import '../models/keypoint.dart';
import '../models/pose_event.dart';

class FormAnalyzer {
  FormAnalyzer({
    this.minConfidence = 0.45,
    this.minTrackedJoints = 5,
    this.framesToConfirm = 4,
    this.maxMatchDistance = 0.85,
    this.enableSmoothing = true,
    this.allowMirroredTemplate = true,
  });

  /// Minimum keypoint confidence accepted from the pose detector.
  final double minConfidence;

  /// Minimum number of reliable joints required before trying to analyze a pose.
  final int minTrackedJoints;

  /// Number of consecutive frames with the same error before emitting an event.
  /// This reduces jitter-driven false positives.
  final int framesToConfirm;

  /// If the closest template frame is still too far, the current pose is treated
  /// as unstable/out-of-template and no event is emitted.
  final double maxMatchDistance;

  /// Applies EMA smoothing on normalized joints to reduce detector jitter.
  final bool enableSmoothing;

  /// Compares against mirrored template variants as well. Useful for front
  /// cameras, mirrored previews, or inconsistent left/right labeling.
  final bool allowMirroredTemplate;

  /// The raw perfect execution template for the current exercise.
  List<List<Keypoint>>? _templateSequence;

  /// Cached normalized template features for fast matching.
  final List<_TemplateFrame> _templateFrames = [];

  /// Small amount of temporal state for stability.
  int? _lastTemplateIndex;
  String? _lastErrorSignature;
  int _sameErrorFrames = 0;
  int _cleanFrames = 0;
  Map<String, _Point> _previousSmoothedPoints = {};

  /// Updates the analyzer with a new template fetched from the backend.
  void setTemplate(List<List<Keypoint>> template) {
    _templateSequence = template;
    _templateFrames.clear();
    _resetTemporalState();

    for (int i = 0; i < template.length; i++) {
      final base = _FrameFeatures.fromRaw(
        template[i],
        minConfidence: minConfidence,
      );

      if (!base.isValid) continue;

      final variants = <_FrameFeatures>[base];

      if (allowMirroredTemplate) {
        variants.add(base.mirroredX());
        variants.add(base.swappedLeftRight());
        variants.add(base.mirroredX().swappedLeftRight());
      }

      _templateFrames.add(_TemplateFrame(index: i, variants: variants));
    }
  }

  /// Analyzes the current frame against the best-matching template frame.
  /// Returns a [PoseEvent] only when a meaningful, stable deviation is detected.
  PoseEvent? analyze({
    required String exercise,
    required List<Keypoint> keypoints,
    required int repCount,
    required double now,
  }) {
    if (_templateSequence == null || _templateSequence!.isEmpty) {
      return null;
    }

    if (_templateFrames.isEmpty) {
      return null;
    }

    final rawCurrent = _FrameFeatures.fromRaw(
      keypoints,
      minConfidence: minConfidence,
    );

    if (!rawCurrent.isValid || rawCurrent.points.length < minTrackedJoints) {
      _registerCleanFrame();
      return null;
    }

    final current = enableSmoothing ? _smooth(rawCurrent) : rawCurrent;
    final match = _findBestTemplateMatch(current, exercise);

    if (match == null || match.distance > _maxAllowedMatchDistance(exercise)) {
      // The person may be partially out of frame, at a very different camera
      // angle, or doing a movement not represented by the template.
      //
      // Push-ups are especially sensitive to camera angle and left/right
      // landmark swaps. If the biomechanics look acceptable, prefer silence
      // over a false correction.
      if (_isPushupExercise(exercise) && _isPushupMechanicallyAcceptable(current)) {
        _registerCleanFrame();
        return null;
      }

      _registerCleanFrame();
      return null;
    }

    _lastTemplateIndex = match.templateIndex;

    final event = _detectDeviations(
      exercise: exercise,
      current: current,
      template: match.features,
      repCount: repCount,
      now: now,
    );

    return _confirmStableEvent(event);
  }

  /// Finds the closest matching template frame using both normalized joint
  /// positions and joint-angle similarity.
  _TemplateMatch? _findBestTemplateMatch(_FrameFeatures current, String exercise) {
    _TemplateMatch? best;

    for (final frame in _templateFrames) {
      for (final variant in frame.variants) {
        final baseDistance = _calculateFeatureDistance(current, variant, exercise);
        if (baseDistance == double.infinity) continue;

        // Soft phase-continuity penalty. This prevents jumping between unrelated
        // phases of the exercise when multiple frames look similar.
        double continuityPenalty = 0.0;
        if (_lastTemplateIndex != null && _templateFrames.length > 3) {
          final jump = (frame.index - _lastTemplateIndex!).abs();
          final normalizedJump = jump / math.max(1, _templateFrames.length - 1);
          continuityPenalty = normalizedJump * 0.04;
        }

        final distance = baseDistance + continuityPenalty;

        if (best == null || distance < best.distance) {
          best = _TemplateMatch(
            templateIndex: frame.index,
            features: variant,
            distance: distance,
          );
        }
      }
    }

    return best;
  }

  /// Composite distance between two normalized skeletons.
  /// Lower is better.
  double _calculateFeatureDistance(_FrameFeatures user, _FrameFeatures template, String exercise) {
    double weightedPositionSum = 0.0;
    double positionWeightSum = 0.0;
    int commonJoints = 0;

    for (final entry in user.points.entries) {
      final id = entry.key;
      final userPoint = entry.value;
      final templatePoint = template.points[id];
      if (templatePoint == null) continue;

      final weight = _jointWeight(id);
      final dx = userPoint.x - templatePoint.x;
      final dy = userPoint.y - templatePoint.y;

      weightedPositionSum += (dx * dx + dy * dy) * weight;
      positionWeightSum += weight;
      commonJoints++;
    }

    if (commonJoints < minTrackedJoints || positionWeightSum == 0.0) {
      return double.infinity;
    }

    final positionDistance = math.sqrt(weightedPositionSum / positionWeightSum);

    double angleSum = 0.0;
    int angleCount = 0;

    for (final entry in user.angles.entries) {
      final templateAngle = template.angles[entry.key];
      if (templateAngle == null) continue;

      final diff = _angleDiffDeg(entry.value, templateAngle);
      final normalized = diff / 180.0;
      angleSum += normalized * normalized;
      angleCount++;
    }

    if (angleCount == 0) {
      return positionDistance;
    }

    final angleDistance = math.sqrt(angleSum / angleCount);

    // Push-ups are usually recorded from different side angles, distances, and
    // body sizes. Angle mechanics are more reliable than exact x/y positions.
    if (_isPushupExercise(exercise)) {
      return (positionDistance * 0.25) + (angleDistance * 0.75);
    }

    // Positions capture phase and shape; angles capture movement mechanics.
    return (positionDistance * 0.55) + (angleDistance * 0.45);
  }

  /// Compares the user's current pose to the selected template pose and extracts
  /// a stable error type + faulty joints.
  PoseEvent? _detectDeviations({
    required String exercise,
    required _FrameFeatures current,
    required _FrameFeatures template,
    required int repCount,
    required double now,
  }) {
    if (_isPushupExercise(exercise)) {
      return _detectPushupDeviations(
        exercise: exercise,
        current: current,
        template: template,
        repCount: repCount,
        now: now,
      );
    }

    final faulty = <String>{};

    // 1) Joint position deviations after body normalization.
    for (final jointId in _criticalJointIds) {
      final userPoint = current.points[jointId];
      final templatePoint = template.points[jointId];
      if (userPoint == null || templatePoint == null) continue;

      final dx = userPoint.x - templatePoint.x;
      final dy = userPoint.y - templatePoint.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      final threshold = _jointDeviationThreshold(jointId);

      if (distance > threshold) {
        final tag = _jointIdToBackendTag(jointId);
        if (tag != null) faulty.add(tag);
      }
    }

    // 2) Angle deviations. These are more robust than raw x/y distances when
    // the camera position changes slightly.
    for (final entry in current.angles.entries) {
      final templateAngle = template.angles[entry.key];
      if (templateAngle == null) continue;

      final diff = _angleDiffDeg(entry.value, templateAngle);
      if (diff > _angleDeviationThreshold(entry.key)) {
        for (final jointId in _angleToCriticalJoints(entry.key)) {
          final tag = _jointIdToBackendTag(jointId);
          if (tag != null) faulty.add(tag);
        }
      }
    }

    if (faulty.isEmpty) {
      return null;
    }

    final faultyJoints = faulty.toList()..sort();
    final errorType = _classifyError(faultyJoints, current, template);

    return PoseEvent(
      exercise: exercise,
      error: errorType,
      faultyJoints: faultyJoints,
      repCount: repCount,
      t: now,
    );
  }

  PoseEvent? _detectPushupDeviations({
    required String exercise,
    required _FrameFeatures current,
    required _FrameFeatures template,
    required int repCount,
    required double now,
  }) {
    final faulty = <String>{};

    final bodyLineProblems = _pushupBodyLineProblems(current, template);
    final elbowProblems = _pushupElbowProblems(current, template);

    // Important: for push-ups, do not emit a correction from x/y mismatch alone.
    // Different camera angles can move shoulders, wrists, hips and ankles a lot
    // in 2D while the exercise is still mechanically correct.
    if (bodyLineProblems.isEmpty && elbowProblems.isEmpty) {
      return null;
    }

    faulty.addAll(bodyLineProblems);
    faulty.addAll(elbowProblems);

    // If the template thinks the pose is far but biomechanical checks are clean,
    // treat it as correct / inconclusive. This fixes many false negatives from
    // side-view videos and different camera heights.
    if (faulty.isEmpty || _isPushupMechanicallyAcceptable(current)) {
      return null;
    }

    final faultyJoints = faulty.toList()..sort();

    String errorType;
    if (faultyJoints.contains(JointTag.spineMid) ||
        faultyJoints.contains(JointTag.leftHip) ||
        faultyJoints.contains(JointTag.rightHip)) {
      errorType = 'curved_back';
    } else {
      errorType = 'form_deviation';
    }

    return PoseEvent(
      exercise: exercise,
      error: errorType,
      faultyJoints: faultyJoints,
      repCount: repCount,
      t: now,
    );
  }

  Set<String> _pushupBodyLineProblems(
    _FrameFeatures current,
    _FrameFeatures template,
  ) {
    final faulty = <String>{};

    final currentLineAngles = <double>[
      ..._availableAngles(current, const [
        'left_body_line_angle',
        'right_body_line_angle',
      ]),
    ];

    final templateLineAngles = <double>[
      ..._availableAngles(template, const [
        'left_body_line_angle',
        'right_body_line_angle',
      ]),
    ];

    final currentWorstLine =
        currentLineAngles.isEmpty ? null : currentLineAngles.reduce(math.min);

    // A correct push-up should keep shoulder-hip-ankle/knee close to a straight
    // line. The threshold is intentionally lenient because pose detectors are
    // noisy in side view and loose clothes can hide hips.
    final hasBadStraightLine =
        currentWorstLine != null && currentWorstLine < 148.0;

    bool deviatesFromTemplate = false;
    if (currentLineAngles.isNotEmpty && templateLineAngles.isNotEmpty) {
      for (final a in currentLineAngles) {
        final closestTemplate = templateLineAngles.reduce(
          (best, b) => (_angleDiffDeg(a, b) < _angleDiffDeg(a, best)) ? b : best,
        );
        if (_angleDiffDeg(a, closestTemplate) > 28.0) {
          deviatesFromTemplate = true;
          break;
        }
      }
    }

    final hipOffset = _maxPushupHipLineOffset(current);
    final hasBadHipOffset = hipOffset != null && hipOffset > 0.20;

    if (hasBadStraightLine || (deviatesFromTemplate && hasBadHipOffset)) {
      faulty.add(JointTag.spineMid);
      faulty.add(JointTag.leftHip);
      faulty.add(JointTag.rightHip);
    }

    return faulty;
  }

  Set<String> _pushupElbowProblems(
    _FrameFeatures current,
    _FrameFeatures template,
  ) {
    final faulty = <String>{};

    // Elbow phase differs a lot between top/middle/bottom. Only flag elbows if
    // the closest template frame strongly disagrees. We return form_deviation
    // without elbow tags to keep the current backend contract safe.
    final currentElbows = _availableAngles(current, const [
      'left_elbow_angle',
      'right_elbow_angle',
    ]);
    final templateElbows = _availableAngles(template, const [
      'left_elbow_angle',
      'right_elbow_angle',
    ]);

    if (currentElbows.isEmpty || templateElbows.isEmpty) return faulty;

    int severe = 0;
    for (final a in currentElbows) {
      final closestTemplate = templateElbows.reduce(
        (best, b) => (_angleDiffDeg(a, b) < _angleDiffDeg(a, best)) ? b : best,
      );
      if (_angleDiffDeg(a, closestTemplate) > 42.0) severe++;
    }

    // Avoid false alarms from one hidden/far-side elbow.
    if (severe >= 2) {
      faulty.add(JointTag.leftHip);
      faulty.add(JointTag.rightHip);
    }

    return faulty;
  }

  bool _isPushupMechanicallyAcceptable(_FrameFeatures current) {
    final lineAngles = _availableAngles(current, const [
      'left_body_line_angle',
      'right_body_line_angle',
    ]);

    final elbowAngles = _availableAngles(current, const [
      'left_elbow_angle',
      'right_elbow_angle',
    ]);

    final hipOffset = _maxPushupHipLineOffset(current);

    final straightBody =
        lineAngles.isNotEmpty && lineAngles.reduce(math.min) >= 150.0;
    final acceptableHipOffset = hipOffset == null || hipOffset <= 0.18;

    // In a correct push-up, elbow angles may be open at top or closed at bottom.
    // They should simply be in a human-plausible range, not equal to the template
    // pixel-for-pixel.
    final plausibleElbows = elbowAngles.isEmpty ||
        elbowAngles.every((angle) => angle >= 45.0 && angle <= 178.0);

    return straightBody && acceptableHipOffset && plausibleElbows;
  }

  List<double> _availableAngles(_FrameFeatures frame, List<String> names) {
    final values = <double>[];
    for (final name in names) {
      final value = frame.angles[name];
      if (value != null && !value.isNaN && !value.isInfinite) {
        values.add(value);
      }
    }
    return values;
  }

  double? _maxPushupHipLineOffset(_FrameFeatures frame) {
    final offsets = <double>[];

    double? sideOffset(String shoulder, String hip, String ankle) {
      final s = frame.points[shoulder];
      final h = frame.points[hip];
      final a = frame.points[ankle];
      if (s == null || h == null || a == null) return null;
      return _pointToLineDistance(h, s, a);
    }

    final left = sideOffset('leftshoulder', 'lefthip', 'leftankle');
    final right = sideOffset('rightshoulder', 'righthip', 'rightankle');

    if (left != null) offsets.add(left);
    if (right != null) offsets.add(right);

    if (offsets.isEmpty) return null;
    return offsets.reduce(math.max);
  }

  double _pointToLineDistance(_Point p, _Point a, _Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final denom = math.sqrt((dx * dx) + (dy * dy));
    if (denom < 1e-8) return 0.0;

    return (((p.x - a.x) * dy) - ((p.y - a.y) * dx)).abs() / denom;
  }

  /// Converts stable low-level deviations into the error names expected by the
  /// backend. Keep this strict and conservative: wrong coaching is worse than
  /// no coaching.
  String _classifyError(
    List<String> faultyJoints,
    _FrameFeatures current,
    _FrameFeatures template,
  ) {
    final hasSpine = faultyJoints.contains(JointTag.spineMid);
    final hasLeftHip = faultyJoints.contains(JointTag.leftHip);
    final hasRightHip = faultyJoints.contains(JointTag.rightHip);
    final hasLeftKnee = faultyJoints.contains(JointTag.leftKnee);
    final hasRightKnee = faultyJoints.contains(JointTag.rightKnee);

    final spineAngleProblem = _hasLargeAngleDeviation(
      current,
      template,
      const ['spine_alignment_left', 'spine_alignment_right'],
      16.0,
    );

    final kneeAngleProblem = _hasLargeAngleDeviation(
      current,
      template,
      const ['left_knee_angle', 'right_knee_angle'],
      18.0,
    );

    final hipAngleProblem = _hasLargeAngleDeviation(
      current,
      template,
      const ['left_hip_angle', 'right_hip_angle'],
      20.0,
    );

    if (hasSpine || spineAngleProblem) {
      return 'curved_back';
    }

    if (hasLeftKnee || hasRightKnee || kneeAngleProblem) {
      // Backward-compatible name with the current backend contract.
      // Technically this means "knee-form deviation" unless you also add
      // explicit knee-vs-toe logic using foot/toe keypoints.
      return 'knee_over_toe';
    }

    if (hasLeftHip || hasRightHip || hipAngleProblem) {
      return 'form_deviation';
    }

    return 'form_deviation';
  }

  bool _hasLargeAngleDeviation(
    _FrameFeatures current,
    _FrameFeatures template,
    List<String> angleNames,
    double thresholdDeg,
  ) {
    for (final name in angleNames) {
      final a = current.angles[name];
      final b = template.angles[name];
      if (a == null || b == null) continue;
      if (_angleDiffDeg(a, b) > thresholdDeg) return true;
    }
    return false;
  }

  PoseEvent? _confirmStableEvent(PoseEvent? event) {
    if (event == null) {
      _registerCleanFrame();
      return null;
    }

    _cleanFrames = 0;

    final sortedJoints = [...event.faultyJoints]..sort();
    final signature = '${event.error}:${sortedJoints.join(',')}';

    if (signature == _lastErrorSignature) {
      _sameErrorFrames++;
    } else {
      _lastErrorSignature = signature;
      _sameErrorFrames = 1;
    }

    if (_sameErrorFrames >= framesToConfirm) {
      return event;
    }

    return null;
  }

  void _registerCleanFrame() {
    _cleanFrames++;

    // Do not reset instantly; a single clean/noisy frame should not erase an
    // otherwise stable deviation sequence.
    if (_cleanFrames >= 2) {
      _lastErrorSignature = null;
      _sameErrorFrames = 0;
    }
  }

  _FrameFeatures _smooth(_FrameFeatures current) {
    if (_previousSmoothedPoints.isEmpty) {
      _previousSmoothedPoints = Map<String, _Point>.from(current.points);
      return current;
    }

    const alpha = 0.65; // Higher = follows current frame faster.
    final smoothed = <String, _Point>{};

    for (final entry in current.points.entries) {
      final previous = _previousSmoothedPoints[entry.key];
      final point = entry.value;

      if (previous == null) {
        smoothed[entry.key] = point;
      } else {
        smoothed[entry.key] = _Point(
          x: (alpha * point.x) + ((1.0 - alpha) * previous.x),
          y: (alpha * point.y) + ((1.0 - alpha) * previous.y),
          confidence: point.confidence,
        );
      }
    }

    _previousSmoothedPoints = smoothed;
    return _FrameFeatures.fromNormalizedPoints(smoothed);
  }

  void _resetTemporalState() {
    _lastTemplateIndex = null;
    _lastErrorSignature = null;
    _sameErrorFrames = 0;
    _cleanFrames = 0;
    _previousSmoothedPoints = {};
  }

  double _maxAllowedMatchDistance(String exercise) {
    if (_isPushupExercise(exercise)) {
      return math.max(maxMatchDistance, 0.95);
    }
    return maxMatchDistance;
  }

  bool _isPushupExercise(String exercise) {
    final normalized = exercise.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    return normalized == 'pushup' ||
        normalized == 'pushups' ||
        normalized == 'pushupexercise';
  }

  double _jointWeight(String id) {
    switch (id) {
      case 'spinemid':
        return 2.4;
      case 'lefthip':
      case 'righthip':
        return 2.0;
      case 'leftknee':
      case 'rightknee':
        return 2.1;
      case 'leftshoulder':
      case 'rightshoulder':
        return 1.6;
      case 'leftankle':
      case 'rightankle':
        return 1.4;
      default:
        return 0.65;
    }
  }

  double _jointDeviationThreshold(String id) {
    switch (id) {
      case 'spinemid':
        return 0.12;
      case 'lefthip':
      case 'righthip':
        return 0.15;
      case 'leftknee':
      case 'rightknee':
        return 0.15;
      case 'leftshoulder':
      case 'rightshoulder':
        return 0.17;
      case 'leftankle':
      case 'rightankle':
        return 0.18;
      default:
        return 0.20;
    }
  }

  double _angleDeviationThreshold(String angleName) {
    switch (angleName) {
      case 'spine_alignment_left':
      case 'spine_alignment_right':
        return 16.0;
      case 'left_knee_angle':
      case 'right_knee_angle':
        return 18.0;
      case 'left_hip_angle':
      case 'right_hip_angle':
        return 20.0;
      default:
        return 22.0;
    }
  }

  List<String> _angleToCriticalJoints(String angleName) {
    switch (angleName) {
      case 'spine_alignment_left':
      case 'spine_alignment_right':
        return const ['spinemid'];
      case 'left_knee_angle':
        return const ['leftknee'];
      case 'right_knee_angle':
        return const ['rightknee'];
      case 'left_hip_angle':
        return const ['lefthip'];
      case 'right_hip_angle':
        return const ['righthip'];
      default:
        return const [];
    }
  }

  String? _jointIdToBackendTag(String id) {
    switch (id) {
      case 'spinemid':
        return JointTag.spineMid;
      case 'leftknee':
        return JointTag.leftKnee;
      case 'rightknee':
        return JointTag.rightKnee;
      case 'lefthip':
        return JointTag.leftHip;
      case 'righthip':
        return JointTag.rightHip;
      // Extra tags are useful for UI highlighting if your backend accepts
      // arbitrary strings in faulty_joints. They are intentionally snake_case.
      case 'leftshoulder':
        return 'left_shoulder';
      case 'rightshoulder':
        return 'right_shoulder';
      case 'leftankle':
        return 'left_ankle';
      case 'rightankle':
        return 'right_ankle';
      default:
        return null;
    }
  }

  static const List<String> _criticalJointIds = [
    'spinemid',
    'leftshoulder',
    'rightshoulder',
    'lefthip',
    'righthip',
    'leftknee',
    'rightknee',
    'leftankle',
    'rightankle',
  ];
}

class _TemplateFrame {
  const _TemplateFrame({
    required this.index,
    required this.variants,
  });

  final int index;
  final List<_FrameFeatures> variants;
}

class _TemplateMatch {
  const _TemplateMatch({
    required this.templateIndex,
    required this.features,
    required this.distance,
  });

  final int templateIndex;
  final _FrameFeatures features;
  final double distance;
}

class _FrameFeatures {
  const _FrameFeatures({
    required this.points,
    required this.angles,
    required this.isValid,
  });

  final Map<String, _Point> points;
  final Map<String, double> angles;
  final bool isValid;

  factory _FrameFeatures.invalid() {
    return const _FrameFeatures(points: {}, angles: {}, isValid: false);
  }

  factory _FrameFeatures.fromRaw(
    List<Keypoint> frame, {
    required double minConfidence,
  }) {
    final rawPoints = <String, _Point>{};

    for (final keypoint in frame) {
      if (keypoint.confidence < minConfidence) continue;

      final id = _normalizeIdName(keypoint.id);
      rawPoints[id] = _Point(
        x: keypoint.x,
        y: keypoint.y,
        confidence: keypoint.confidence,
      );
    }

    if (rawPoints.length < 2) {
      return _FrameFeatures.invalid();
    }

    final center = _estimateBodyCenter(rawPoints);
    final scale = _estimateBodyScale(rawPoints);

    if (scale <= 1e-6 || scale.isNaN || scale.isInfinite) {
      return _FrameFeatures.invalid();
    }

    final normalized = <String, _Point>{};
    for (final entry in rawPoints.entries) {
      normalized[entry.key] = _Point(
        x: (entry.value.x - center.x) / scale,
        y: (entry.value.y - center.y) / scale,
        confidence: entry.value.confidence,
      );
    }

    final rotation = _rotationToUpright(normalized);
    final rotated = _rotatePoints(normalized, rotation);

    return _FrameFeatures.fromNormalizedPoints(rotated);
  }

  factory _FrameFeatures.fromNormalizedPoints(Map<String, _Point> points) {
    if (points.length < 2) {
      return _FrameFeatures.invalid();
    }

    return _FrameFeatures(
      points: Map<String, _Point>.from(points),
      angles: _calculateAngles(points),
      isValid: true,
    );
  }

  _FrameFeatures mirroredX() {
    final mirrored = <String, _Point>{};

    for (final entry in points.entries) {
      mirrored[entry.key] = _Point(
        x: -entry.value.x,
        y: entry.value.y,
        confidence: entry.value.confidence,
      );
    }

    return _FrameFeatures.fromNormalizedPoints(mirrored);
  }

  _FrameFeatures swappedLeftRight() {
    final swapped = <String, _Point>{};

    for (final entry in points.entries) {
      swapped[_swapLeftRightId(entry.key)] = entry.value;
    }

    return _FrameFeatures.fromNormalizedPoints(swapped);
  }
}

class _Point {
  const _Point({
    required this.x,
    required this.y,
    required this.confidence,
  });

  final double x;
  final double y;
  final double confidence;
}

String _normalizeIdName(KeypointId id) {
  // Works with Dart enums such as KeypointId.leftKnee.
  final raw = id.name;
  return _canonicalName(raw);
}

String _canonicalName(String value) {
  return value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
}

String _swapLeftRightId(String id) {
  if (id.startsWith('left')) {
    return 'right${id.substring(4)}';
  }
  if (id.startsWith('right')) {
    return 'left${id.substring(5)}';
  }
  return id;
}

_Point _estimateBodyCenter(Map<String, _Point> points) {
  final leftHip = points['lefthip'];
  final rightHip = points['righthip'];
  final spineMid = points['spinemid'];

  if (leftHip != null && rightHip != null) {
    return _midpoint(leftHip, rightHip);
  }

  if (spineMid != null) {
    return spineMid;
  }

  double x = 0.0;
  double y = 0.0;
  for (final point in points.values) {
    x += point.x;
    y += point.y;
  }

  return _Point(
    x: x / points.length,
    y: y / points.length,
    confidence: 1.0,
  );
}

double _estimateBodyScale(Map<String, _Point> points) {
  final leftShoulder = points['leftshoulder'];
  final rightShoulder = points['rightshoulder'];
  final leftHip = points['lefthip'];
  final rightHip = points['righthip'];

  final shoulderCenter =
      leftShoulder != null && rightShoulder != null ? _midpoint(leftShoulder, rightShoulder) : null;
  final hipCenter = leftHip != null && rightHip != null ? _midpoint(leftHip, rightHip) : null;

  final candidates = <double>[];

  if (shoulderCenter != null && hipCenter != null) {
    candidates.add(_distance(shoulderCenter, hipCenter) * 2.2);
  }

  if (leftShoulder != null && rightShoulder != null) {
    candidates.add(_distance(leftShoulder, rightShoulder) * 2.5);
  }

  if (leftHip != null && rightHip != null) {
    candidates.add(_distance(leftHip, rightHip) * 3.2);
  }

  // Fallback: bounding-box diagonal of reliable points.
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

  if (bboxDiagonal > 0.0) {
    candidates.add(bboxDiagonal);
  }

  if (candidates.isEmpty) return 1.0;

  candidates.sort();
  return candidates[candidates.length ~/ 2]; // median is robust to outliers
}

double _rotationToUpright(Map<String, _Point> points) {
  final leftShoulder = points['leftshoulder'];
  final rightShoulder = points['rightshoulder'];
  final leftHip = points['lefthip'];
  final rightHip = points['righthip'];

  if (leftShoulder == null || rightShoulder == null || leftHip == null || rightHip == null) {
    return 0.0;
  }

  final shoulderCenter = _midpoint(leftShoulder, rightShoulder);
  final hipCenter = _midpoint(leftHip, rightHip);

  final vx = shoulderCenter.x - hipCenter.x;
  final vy = shoulderCenter.y - hipCenter.y;

  if ((vx * vx + vy * vy) < 1e-8) return 0.0;

  // In image coordinates, y grows downward. The upright torso vector points up,
  // which is approximately angle -pi/2.
  final currentAngle = math.atan2(vy, vx);
  const targetAngle = -math.pi / 2.0;
  return targetAngle - currentAngle;
}

Map<String, _Point> _rotatePoints(Map<String, _Point> points, double angleRad) {
  if (angleRad.abs() < 1e-6) return points;

  final cosA = math.cos(angleRad);
  final sinA = math.sin(angleRad);
  final rotated = <String, _Point>{};

  for (final entry in points.entries) {
    final x = entry.value.x;
    final y = entry.value.y;

    rotated[entry.key] = _Point(
      x: (x * cosA) - (y * sinA),
      y: (x * sinA) + (y * cosA),
      confidence: entry.value.confidence,
    );
  }

  return rotated;
}

Map<String, double> _calculateAngles(Map<String, _Point> points) {
  final angles = <String, double>{};

  void addAngle(String name, String a, String b, String c) {
    final p1 = points[a];
    final p2 = points[b];
    final p3 = points[c];

    if (p1 == null || p2 == null || p3 == null) return;
    angles[name] = _angleAtPointDeg(p1, p2, p3);
  }

  // Lower body mechanics.
  addAngle('left_knee_angle', 'lefthip', 'leftknee', 'leftankle');
  addAngle('right_knee_angle', 'righthip', 'rightknee', 'rightankle');
  addAngle('left_hip_angle', 'leftshoulder', 'lefthip', 'leftknee');
  addAngle('right_hip_angle', 'rightshoulder', 'righthip', 'rightknee');

  // Upper body mechanics for push-ups.
  addAngle('left_elbow_angle', 'leftshoulder', 'leftelbow', 'leftwrist');
  addAngle('right_elbow_angle', 'rightshoulder', 'rightelbow', 'rightwrist');
  addAngle('left_shoulder_angle', 'leftelbow', 'leftshoulder', 'lefthip');
  addAngle('right_shoulder_angle', 'rightelbow', 'rightshoulder', 'righthip');

  // Full-body push-up line. Straight body should be close to 180 degrees.
  addAngle('left_body_line_angle', 'leftshoulder', 'lefthip', 'leftankle');
  addAngle('right_body_line_angle', 'rightshoulder', 'righthip', 'rightankle');
  addAngle('left_body_line_knee_angle', 'leftshoulder', 'lefthip', 'leftknee');
  addAngle('right_body_line_knee_angle', 'rightshoulder', 'righthip', 'rightknee');

  // Back/spine alignment if spineMid exists in your model.
  addAngle('spine_alignment_left', 'leftshoulder', 'spinemid', 'lefthip');
  addAngle('spine_alignment_right', 'rightshoulder', 'spinemid', 'righthip');

  return angles;
}

double _angleAtPointDeg(_Point a, _Point b, _Point c) {
  final abx = a.x - b.x;
  final aby = a.y - b.y;
  final cbx = c.x - b.x;
  final cby = c.y - b.y;

  final dot = (abx * cbx) + (aby * cby);
  final magAB = math.sqrt((abx * abx) + (aby * aby));
  final magCB = math.sqrt((cbx * cbx) + (cby * cby));

  if (magAB < 1e-8 || magCB < 1e-8) return 0.0;

  final cosValue = (dot / (magAB * magCB)).clamp(-1.0, 1.0);
  return math.acos(cosValue) * 180.0 / math.pi;
}

double _angleDiffDeg(double a, double b) {
  final diff = (a - b).abs();
  return math.min(diff, 360.0 - diff);
}

_Point _midpoint(_Point a, _Point b) {
  return _Point(
    x: (a.x + b.x) / 2.0,
    y: (a.y + b.y) / 2.0,
    confidence: math.min(a.confidence, b.confidence),
  );
}

double _distance(_Point a, _Point b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt((dx * dx) + (dy * dy));
}
