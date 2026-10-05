import 'dart:math' as math;
import '../models/keypoint.dart';
import 'prayer_reference.dart';

enum CalibrationIssue {
  noBody,
  visibility,
  framing,
  tooFar,
  tooClose,
  center,
  posture,
  angle,
  holding,
  ready
}

class CalibrationReading {
  const CalibrationReading(this.issue, {this.progress = 0});
  final CalibrationIssue issue;
  final double progress;
  bool get ready => issue == CalibrationIssue.ready;
}

/// Approximate view matching from projected torso proportions, not a measured camera yaw.
class PrayerCalibration {
  PrayerCalibration(this.reference,
      {this.hold = const Duration(milliseconds: 1500),
      this.maxGap = const Duration(milliseconds: 400),
      this.minimumFrames = 8}) {
    _target =
        _signature(reference.standing.preview, reference.standing.aspectRatio);
    if (_target == null) {
      throw const FormatException(
          'صورة القيام المرجعية غير واضحة للضبط؛ اختر صورة أخرى وأعد التفعيل.');
    }
  }
  final PrayerReference reference;
  final Duration hold, maxGap;
  final int minimumFrames;
  List<double>? _target;
  List<double>? _anchor;
  DateTime? _since, _last;
  int _frames = 0;
  CalibrationReading reading =
      const CalibrationReading(CalibrationIssue.noBody);

  static const requiredIds = [
    KeypointId.nose,
    KeypointId.leftShoulder,
    KeypointId.rightShoulder,
    KeypointId.leftHip,
    KeypointId.rightHip,
    KeypointId.leftKnee,
    KeypointId.rightKnee,
    KeypointId.leftAnkle,
    KeypointId.rightAnkle
  ];

  bool isReady(DateTime now) =>
      reading.ready &&
      _last != null &&
      !now.isBefore(_last!) &&
      now.difference(_last!) <= maxGap;

  void reset() {
    _since = null;
    _last = null;
    _frames = 0;
    _anchor = null;
    reading = const CalibrationReading(CalibrationIssue.noBody);
  }

  CalibrationReading observe(
      List<Keypoint> points, double aspect, DateTime now) {
    if (_last != null && !now.isAfter(_last!)) return reading;
    if (_last != null && now.difference(_last!) > maxGap) {
      _since = null;
      _frames = 0;
      _anchor = null;
    }
    _last = now;
    final issue = check(points, aspect);
    if (issue != null) {
      _since = null;
      _frames = 0;
      _anchor = null;
      return reading = CalibrationReading(issue);
    }
    final signature = _signature(points, aspect)!;
    final map = {for (final p in points) p.id: p};
    final hipX = (map[KeypointId.leftHip]!.x + map[KeypointId.rightHip]!.x) / 2;
    final body = requiredIds.map((id) => map[id]!).toList();
    final height = body.map((p) => p.y).reduce(math.max) -
        body.map((p) => p.y).reduce(math.min);
    final snapshot = [...signature, hipX, height];
    if (_anchor != null &&
        List.generate(5, (i) => i).any(
            (i) => (snapshot[i] - _anchor![i]).abs() > (i < 3 ? .10 : .04))) {
      _since = null;
      _frames = 0;
      _anchor = null;
    }
    _anchor ??= snapshot;
    _since ??= now;
    _frames++;
    final progress = math.min(
        1.0, now.difference(_since!).inMilliseconds / hold.inMilliseconds);
    return reading = CalibrationReading(
        progress >= 1 && _frames >= minimumFrames
            ? CalibrationIssue.ready
            : CalibrationIssue.holding,
        progress: progress);
  }

  CalibrationIssue? check(List<Keypoint> points, double aspect) {
    if (points.isEmpty) return CalibrationIssue.noBody;
    final map = {for (final p in points) p.id: p};
    if (!requiredIds.every((id) => map.containsKey(id) && _visible(map[id]!))) {
      return CalibrationIssue.visibility;
    }
    final body = requiredIds.map((id) => map[id]!).toList();
    if (body.any((p) => p.x < .04 || p.x > .96 || p.y < .04 || p.y > .96)) {
      return CalibrationIssue.framing;
    }
    final top = body.map((p) => p.y).reduce(math.min),
        bottom = body.map((p) => p.y).reduce(math.max);
    final height = bottom - top;
    if (height < .55) return CalibrationIssue.tooFar;
    if (height > .86) return CalibrationIssue.tooClose;
    final hipX = (map[KeypointId.leftHip]!.x + map[KeypointId.rightHip]!.x) / 2;
    if ((hipX - .5).abs() > .13) return CalibrationIssue.center;
    final signature = _signature(points, aspect);
    if (signature == null) return CalibrationIssue.posture;
    for (var i = 0; i < 3; i++) {
      // Starter tolerances; deliberately not presented as calibrated degree accuracy.
      final tolerance = i == 2 ? .25 : .18;
      if ((signature[i] - _target![i]).abs() > tolerance) {
        return CalibrationIssue.angle;
      }
    }
    return null;
  }

  static bool _visible(Keypoint p) =>
      p.confidence.isFinite &&
      p.confidence >= .65 &&
      p.confidence <= 1 &&
      p.x.isFinite &&
      p.y.isFinite &&
      p.x >= 0 &&
      p.x <= 1 &&
      p.y >= 0 &&
      p.y <= 1;

  static List<double>? _signature(List<Keypoint> points, double aspect) {
    if (!aspect.isFinite || aspect <= 0) return null;
    final m = {
      for (final p in points)
        if (_visible(p)) p.id: (p.x * aspect, p.y)
    };
    if (!requiredIds.every(m.containsKey)) return null;
    final ls = m[KeypointId.leftShoulder]!, rs = m[KeypointId.rightShoulder]!;
    final lh = m[KeypointId.leftHip]!, rh = m[KeypointId.rightHip]!;
    final sx = (ls.$1 + rs.$1) / 2,
        sy = (ls.$2 + rs.$2) / 2,
        hx = (lh.$1 + rh.$1) / 2,
        hy = (lh.$2 + rh.$2) / 2;
    final torso = math.sqrt(math.pow(sx - hx, 2) + math.pow(sy - hy, 2));
    if (torso < .04 || sy >= hy || (sx - hx).abs() / torso > .35) return null;
    for (final ids in const [
      [KeypointId.leftHip, KeypointId.leftKnee, KeypointId.leftAnkle],
      [KeypointId.rightHip, KeypointId.rightKnee, KeypointId.rightAnkle]
    ]) {
      final h = m[ids[0]]!, k = m[ids[1]]!, a = m[ids[2]]!;
      final u = (h.$1 - k.$1, h.$2 - k.$2), v = (a.$1 - k.$1, a.$2 - k.$2);
      final length =
          math.sqrt((u.$1 * u.$1 + u.$2 * u.$2) * (v.$1 * v.$1 + v.$2 * v.$2));
      if (length < .001 ||
          k.$2 < hy ||
          a.$2 < k.$2 ||
          math.acos(((u.$1 * v.$1 + u.$2 * v.$2) / length).clamp(-1, 1)) *
                  180 /
                  math.pi <
              150) {
        return null;
      }
    }
    return [
      (ls.$1 - rs.$1).abs() / torso,
      (lh.$1 - rh.$1).abs() / torso,
      (m[KeypointId.nose]!.$1 - sx) / torso
    ];
  }
}
