import 'dart:math' as math;
import '../models/keypoint.dart';
import 'prayer_definition.dart';
import 'prayer_sequence_engine.dart';

/// Tunable physical geometry only; no prayer meaning or content here.
class PrayerPoseThresholds {
  const PrayerPoseThresholds(
      {this.minJointConfidence = 0.65,
      this.straightKneeDegrees = 155,
      this.foldedKneeDegrees = 135,
      this.uprightRatio = 0.35,
      this.horizontalRatio = 0.55,
      this.sujoodHeadDepth = 0.25});
  final double minJointConfidence, straightKneeDegrees, foldedKneeDegrees;
  final double uprightRatio, horizontalRatio, sujoodHeadDepth;
}

class PrayerPoseClassifier {
  const PrayerPoseClassifier({this.thresholds = const PrayerPoseThresholds()});
  final PrayerPoseThresholds thresholds;

  PoseObservation classify(List<Keypoint> points, {double aspectRatio = 1}) {
    if (!aspectRatio.isFinite || aspectRatio <= 0) {
      return const PoseObservation(PrayerPose.unknown, 0);
    }
    final map = {for (final p in points) p.id: p};
    PoseObservation? best;
    // Use one fully visible side rather than averaging occluded joints.
    for (final ids in const [
      [
        KeypointId.leftShoulder,
        KeypointId.leftHip,
        KeypointId.leftKnee,
        KeypointId.leftAnkle
      ],
      [
        KeypointId.rightShoulder,
        KeypointId.rightHip,
        KeypointId.rightKnee,
        KeypointId.rightAnkle
      ],
    ]) {
      final side = ids.map((id) => map[id]).toList();
      if (side.any((p) =>
          p == null ||
          !p.x.isFinite ||
          !p.y.isFinite ||
          !p.confidence.isFinite ||
          p.confidence < thresholds.minJointConfidence ||
          p.confidence > 1 ||
          p.x < 0 ||
          p.x > 1 ||
          p.y < 0 ||
          p.y > 1)) {
        continue;
      }
      final s = side[0]!, h = side[1]!, k = side[2]!, a = side[3]!;
      final torso = math.sqrt(
          math.pow((s.x - h.x) * aspectRatio, 2) + math.pow(s.y - h.y, 2));
      if (torso < 0.04) continue;
      final knee = _angle(h, k, a, aspectRatio);
      final hip = _angle(s, h, k, aspectRatio);
      if (knee == null || hip == null) continue;
      final upright = s.y < h.y &&
          (s.x - h.x).abs() * aspectRatio / torso < thresholds.uprightRatio;
      final horizontal = (s.y - h.y).abs() / torso < thresholds.horizontalRatio;
      final folded = knee < thresholds.foldedKneeDegrees;
      PrayerPose pose = PrayerPose.unknown;
      if (upright && knee > thresholds.straightKneeDegrees && hip > 150) {
        pose = PrayerPose.standing;
      } else if (horizontal &&
          knee > thresholds.straightKneeDegrees &&
          hip < 130) {
        pose = PrayerPose.ruku;
      } else if (folded && s.y - h.y > torso * thresholds.sujoodHeadDepth) {
        pose = PrayerPose.sujood;
      } else if (folded && upright) {
        pose = PrayerPose.sitting;
      }
      final confidence = side.map((p) => p!.confidence).reduce(math.min);
      final result = PoseObservation(pose, confidence);
      if (pose != PrayerPose.unknown &&
          (best == null || confidence > best.confidence)) {
        best = result;
      }
    }
    return best ?? const PoseObservation(PrayerPose.unknown, 0);
  }

  double? _angle(Keypoint a, Keypoint b, Keypoint c, double aspectRatio) {
    final ux = (a.x - b.x) * aspectRatio, uy = a.y - b.y;
    final vx = (c.x - b.x) * aspectRatio, vy = c.y - b.y;
    final length = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    if (length < 0.0001) return null;
    return math.acos(((ux * vx + uy * vy) / length).clamp(-1.0, 1.0)) *
        180 /
        math.pi;
  }
}
