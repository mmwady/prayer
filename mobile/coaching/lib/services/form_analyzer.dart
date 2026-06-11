// ─────────────────────────────────────────────────────────────────────────────
// form_analyzer.dart
//
// Conservative on-device form analyzer.
//
// The backend owns exercise-specific thresholds in:
//   backend/data/exercise_rules/<exercise>.json
// The mobile app loads that JSON and injects it here through setExerciseRules().
// This keeps the analyzer extensible while preserving fast on-device checks.
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

  final double minConfidence;
  final int minTrackedJoints;
  final int framesToConfirm;
  final double maxMatchDistance;
  final bool enableSmoothing;
  final bool allowMirroredTemplate;

  final List<_TemplateFrame> _templateFrames = [];
  Map<String, dynamic> _exerciseRules = const {};
  Map<String, _Point> _previousSmoothedPoints = {};
  String? _lastErrorSignature;
  int _sameErrorFrames = 0;
  int _cleanFrames = 0;

  /// Injects rules loaded from `/api/v1/exercise-rules/<exercise>`.
  ///
  /// Expected shape:
  /// {
  ///   "analysis": {
  ///     "rules": [
  ///       {"id": "knee_supported_pushup", "enabled": true,
  ///        "thresholds": {"bent_knee_max_deg": 150.0}}
  ///     ]
  ///   }
  /// }
  void setExerciseRules(Map<String, dynamic>? rules) {
    _exerciseRules = rules ?? const {};
    _resetTemporalState();
  }

  void setTemplate(List<List<Keypoint>> template) {
    _templateFrames.clear();
    _resetTemporalState();

    for (var i = 0; i < template.length; i++) {
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

  PoseEvent? analyze({
    required String exercise,
    required List<Keypoint> keypoints,
    required int repCount,
    required double now,
  }) {
    final rawCurrent = _FrameFeatures.fromRaw(
      keypoints,
      minConfidence: minConfidence,
    );

    if (!rawCurrent.isValid || rawCurrent.points.length < minTrackedJoints) {
      _registerCleanFrame();
      return null;
    }

    final current = enableSmoothing ? _smooth(rawCurrent) : rawCurrent;

    if (_isPushupExercise(exercise)) {
      return _confirmStableEvent(_detectPushup(
        exercise: exercise,
        current: current,
        repCount: repCount,
        now: now,
      ));
    }

    if (_templateFrames.isEmpty) {
      _registerCleanFrame();
      return null;
    }

    final match = _findBestTemplateMatch(current, exercise);
    if (match == null || match.distance > maxMatchDistance) {
      _registerCleanFrame();
      return null;
    }

    return _confirmStableEvent(_detectGenericDeviation(
      exercise: exercise,
      current: current,
      template: match.features,
      repCount: repCount,
      now: now,
    ));
  }

  PoseEvent? _detectPushup({
    required String exercise,
    required _FrameFeatures current,
    required int repCount,
    required double now,
  }) {
    if (_ruleEnabled('knee_supported_pushup') &&
        _detectKneeSupportedPushup(current)) {
      return PoseEvent(
        exercise: exercise,
        error: 'knee_supported_pushup',
        faultyJoints: _faultyJointsForRule(
          'knee_supported_pushup',
          const [
            JointTag.leftKnee,
            JointTag.rightKnee,
            JointTag.leftHip,
            JointTag.rightHip,
          ],
        ),
        repCount: repCount,
        t: now,
      );
    }

    if (!_ruleEnabled('curved_back')) {
      return null;
    }

    final faulty = <String>{};
    final bodyLineAngles = _availableAngles(current, const [
      'left_body_line_angle',
      'right_body_line_angle',
    ]);
    final worstBodyLine =
        bodyLineAngles.isEmpty ? null : bodyLineAngles.reduce(math.min);
    final hipOffset = _maxPushupHipLineOffset(current);

    final bodyLineMinDeg = _threshold(
      'curved_back',
      'body_line_min_deg',
      148.0,
    );
    final hipLineOffsetMax = _threshold(
      'curved_back',
      'hip_line_offset_max',
      0.20,
    );

    if ((worstBodyLine != null && worstBodyLine < bodyLineMinDeg) ||
        (hipOffset != null && hipOffset > hipLineOffsetMax)) {
      faulty.addAll(_faultyJointsForRule(
        'curved_back',
        const [JointTag.spineMid, JointTag.leftHip, JointTag.rightHip],
      ));
    }

    if (faulty.isEmpty) return null;

    return PoseEvent(
      exercise: exercise,
      error: 'curved_back',
      faultyJoints: (faulty.toList()..sort()),
      repCount: repCount,
      t: now,
    );
  }

  /// Detects modified/knee push-ups when the requested exercise is full push-up.
  bool _detectKneeSupportedPushup(_FrameFeatures current) {
    final kneeAngles = _availableAngles(current, const [
      'left_knee_angle',
      'right_knee_angle',
    ]);

    final ankleBodyLines = _availableAngles(current, const [
      'left_body_line_angle',
      'right_body_line_angle',
    ]);

    final kneeBodyLines = _availableAngles(current, const [
      'left_body_line_knee_angle',
      'right_body_line_knee_angle',
    ]);

    final elbowAngles = _availableAngles(current, const [
      'left_elbow_angle',
      'right_elbow_angle',
    ]);

    final hasPushupArms = elbowAngles.isEmpty ||
        elbowAngles.any((angle) => angle >= 45.0 && angle <= 178.0);

    final bentKneeMin = _threshold(
      'knee_supported_pushup',
      'bent_knee_min_deg',
      20.0,
    );
    final bentKneeMax = _threshold(
      'knee_supported_pushup',
      'bent_knee_max_deg',
      150.0,
    );
    final kneeBodyLineMin = _threshold(
      'knee_supported_pushup',
      'knee_body_line_min_deg',
      158.0,
    );
    final ankleBodyLineMax = _threshold(
      'knee_supported_pushup',
      'ankle_body_line_max_deg',
      155.0,
    );

    final clearlyBentKnee = kneeAngles
            .where((angle) => angle > bentKneeMin && angle < bentKneeMax)
            .length >=
        1;

    final ankleLineBroken = ankleBodyLines.isNotEmpty &&
        ankleBodyLines.reduce(math.min) < ankleBodyLineMax;

    final kneeLineStraight = kneeBodyLines.isNotEmpty &&
        kneeBodyLines.reduce(math.max) > kneeBodyLineMin;

    if (hasPushupArms && clearlyBentKnee && kneeLineStraight) return true;
    if (hasPushupArms && clearlyBentKnee && ankleLineBroken) return true;
    return false;
  }

  PoseEvent? _detectGenericDeviation({
    required String exercise,
    required _FrameFeatures current,
    required _FrameFeatures template,
    required int repCount,
    required double now,
  }) {
    final faulty = <String>{};

    for (final jointId in _criticalJointIds) {
      final userPoint = current.points[jointId];
      final templatePoint = template.points[jointId];
      if (userPoint == null || templatePoint == null) continue;

      final distance = _distance(userPoint, templatePoint);
      if (distance > _jointDeviationThreshold(jointId)) {
        final tag = _jointIdToBackendTag(jointId);
        if (tag != null) faulty.add(tag);
      }
    }

    if (faulty.isEmpty) return null;

    return PoseEvent(
      exercise: exercise,
      error: _classifyGenericError(faulty),
      faultyJoints: (faulty.toList()..sort()),
      repCount: repCount,
      t: now,
    );
  }

  _TemplateMatch? _findBestTemplateMatch(_FrameFeatures current, String exercise) {
    _TemplateMatch? best;

    for (final frame in _templateFrames) {
      for (final variant in frame.variants) {
        final distance = _calculateFeatureDistance(current, variant, exercise);
        if (distance == double.infinity) continue;

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

  double _calculateFeatureDistance(
    _FrameFeatures user,
    _FrameFeatures template,
    String exercise,
  ) {
    double positionSum = 0.0;
    double weightSum = 0.0;
    var commonJoints = 0;

    for (final entry in user.points.entries) {
      final templatePoint = template.points[entry.key];
      if (templatePoint == null) continue;

      final weight = _jointWeight(entry.key);
      final dx = entry.value.x - templatePoint.x;
      final dy = entry.value.y - templatePoint.y;
      positionSum += (dx * dx + dy * dy) * weight;
      weightSum += weight;
      commonJoints += 1;
    }

    if (commonJoints < minTrackedJoints || weightSum == 0.0) {
      return double.infinity;
    }

    final positionDistance = math.sqrt(positionSum / weightSum);

    double angleSum = 0.0;
    var angleCount = 0;
    for (final entry in user.angles.entries) {
      final templateAngle = template.angles[entry.key];
      if (templateAngle == null) continue;

      final normalized = _angleDiffDeg(entry.value, templateAngle) / 180.0;
      angleSum += normalized * normalized;
      angleCount += 1;
    }

    if (angleCount == 0) return positionDistance;

    final angleDistance = math.sqrt(angleSum / angleCount);
    return _isPushupExercise(exercise)
        ? (positionDistance * 0.25) + (angleDistance * 0.75)
        : (positionDistance * 0.55) + (angleDistance * 0.45);
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
      _sameErrorFrames += 1;
    } else {
      _lastErrorSignature = signature;
      _sameErrorFrames = 1;
    }

    final requiredFrames = _analysisInt('frames_to_confirm', framesToConfirm);
    return _sameErrorFrames >= requiredFrames ? event : null;
  }

  void _registerCleanFrame() {
    _cleanFrames += 1;
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

    const alpha = 0.65;
    final smoothed = <String, _Point>{};
    for (final entry in current.points.entries) {
      final previous = _previousSmoothedPoints[entry.key];
      final point = entry.value;
      smoothed[entry.key] = previous == null
          ? point
          : _Point(
              x: (alpha * point.x) + ((1.0 - alpha) * previous.x),
              y: (alpha * point.y) + ((1.0 - alpha) * previous.y),
              confidence: point.confidence,
            );
    }

    _previousSmoothedPoints = smoothed;
    return _FrameFeatures.fromNormalizedPoints(smoothed);
  }

  void _resetTemporalState() {
    _lastErrorSignature = null;
    _sameErrorFrames = 0;
    _cleanFrames = 0;
    _previousSmoothedPoints = {};
  }

  Map<String, dynamic>? _analysisMap() {
    final analysis = _exerciseRules['analysis'];
    return analysis is Map<String, dynamic> ? analysis : null;
  }

  int _analysisInt(String key, int fallback) {
    final value = _analysisMap()?[key];
    return value is num ? value.toInt() : fallback;
  }

  Map<String, dynamic>? _rule(String ruleId) {
    final rules = _analysisMap()?['rules'];
    if (rules is! List) return null;

    for (final item in rules) {
      if (item is Map<String, dynamic> && item['id'] == ruleId) return item;
    }
    return null;
  }

  bool _ruleEnabled(String ruleId) {
    final rule = _rule(ruleId);
    if (rule == null) return true;
    return rule['enabled'] != false;
  }

  double _threshold(String ruleId, String thresholdName, double fallback) {
    final rule = _rule(ruleId);
    final thresholds = rule?['thresholds'];
    if (thresholds is Map<String, dynamic>) {
      final value = thresholds[thresholdName];
      if (value is num) return value.toDouble();
    }
    return fallback;
  }

  List<String> _faultyJointsForRule(String ruleId, List<String> fallback) {
    final value = _rule(ruleId)?['faulty_joints'];
    if (value is List) {
      final joints = value.whereType<String>().toList();
      if (joints.isNotEmpty) return joints;
    }
    return fallback;
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

  String _classifyGenericError(Set<String> faulty) {
    if (faulty.contains(JointTag.spineMid)) return 'curved_back';
    if (faulty.contains(JointTag.leftKnee) ||
        faulty.contains(JointTag.rightKnee)) {
      return 'knee_over_toe';
    }
    return 'form_deviation';
  }

  bool _isPushupExercise(String exercise) {
    final normalized =
        exercise.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
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
      case 'leftknee':
      case 'rightknee':
        return 2.0;
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
  const _TemplateFrame({required this.index, required this.variants});
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
      rawPoints[_normalizeIdName(keypoint.id)] = _Point(
        x: keypoint.x,
        y: keypoint.y,
        confidence: keypoint.confidence,
      );
    }

    if (rawPoints.length < 2) return _FrameFeatures.invalid();

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

    final rotated = _rotatePoints(normalized, _rotationToUpright(normalized));
    return _FrameFeatures.fromNormalizedPoints(rotated);
  }

  factory _FrameFeatures.fromNormalizedPoints(Map<String, _Point> points) {
    if (points.length < 2) return _FrameFeatures.invalid();
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
  const _Point({required this.x, required this.y, required this.confidence});
  final double x;
  final double y;
  final double confidence;
}

String _normalizeIdName(KeypointId id) => _canonicalName(id.name);
String _canonicalName(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

String _swapLeftRightId(String id) {
  if (id.startsWith('left')) return 'right${id.substring(4)}';
  if (id.startsWith('right')) return 'left${id.substring(5)}';
  return id;
}

_Point _estimateBodyCenter(Map<String, _Point> points) {
  final leftHip = points['lefthip'];
  final rightHip = points['righthip'];
  final spineMid = points['spinemid'];

  if (leftHip != null && rightHip != null) return _midpoint(leftHip, rightHip);
  if (spineMid != null) return spineMid;

  double x = 0.0;
  double y = 0.0;
  for (final point in points.values) {
    x += point.x;
    y += point.y;
  }

  return _Point(x: x / points.length, y: y / points.length, confidence: 1.0);
}

double _estimateBodyScale(Map<String, _Point> points) {
  final leftShoulder = points['leftshoulder'];
  final rightShoulder = points['rightshoulder'];
  final leftHip = points['lefthip'];
  final rightHip = points['righthip'];

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

double _rotationToUpright(Map<String, _Point> points) {
  final leftShoulder = points['leftshoulder'];
  final rightShoulder = points['rightshoulder'];
  final leftHip = points['lefthip'];
  final rightHip = points['righthip'];

  if (leftShoulder == null ||
      rightShoulder == null ||
      leftHip == null ||
      rightHip == null) {
    return 0.0;
  }

  final shoulderCenter = _midpoint(leftShoulder, rightShoulder);
  final hipCenter = _midpoint(leftHip, rightHip);
  final vx = shoulderCenter.x - hipCenter.x;
  final vy = shoulderCenter.y - hipCenter.y;
  if ((vx * vx + vy * vy) < 1e-8) return 0.0;

  return (-math.pi / 2.0) - math.atan2(vy, vx);
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

  addAngle('left_knee_angle', 'lefthip', 'leftknee', 'leftankle');
  addAngle('right_knee_angle', 'righthip', 'rightknee', 'rightankle');
  addAngle('left_hip_angle', 'leftshoulder', 'lefthip', 'leftknee');
  addAngle('right_hip_angle', 'rightshoulder', 'righthip', 'rightknee');
  addAngle('left_elbow_angle', 'leftshoulder', 'leftelbow', 'leftwrist');
  addAngle('right_elbow_angle', 'rightshoulder', 'rightelbow', 'rightwrist');
  addAngle('left_body_line_angle', 'leftshoulder', 'lefthip', 'leftankle');
  addAngle('right_body_line_angle', 'rightshoulder', 'righthip', 'rightankle');
  addAngle('left_body_line_knee_angle', 'leftshoulder', 'lefthip', 'leftknee');
  addAngle('right_body_line_knee_angle', 'rightshoulder', 'righthip', 'rightknee');

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
