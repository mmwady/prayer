import '../models/keypoint.dart';
import 'prayer_definition.dart';
import 'prayer_pose_classifier.dart';

enum FloorCheckPhase { off, ruku, sujood, completed }

/// Optional pre-session coverage probe. Its observations never enter the prayer engine.
class PrayerFloorCheck {
  FloorCheckPhase phase = FloorCheckPhase.off;
  DateTime? _since, _last;
  int _frames = 0;
  bool visible = false;
  bool get active =>
      phase == FloorCheckPhase.ruku || phase == FloorCheckPhase.sujood;
  void start() {
    phase = FloorCheckPhase.ruku;
    _since = null;
    _last = null;
    _frames = 0;
    visible = false;
  }

  void observe(List<Keypoint> points, double aspect, DateTime now) {
    if (!active || (_last != null && !now.isAfter(_last!))) return;
    if (_last != null &&
        now.difference(_last!) > const Duration(milliseconds: 400)) {
      _since = null;
      _frames = 0;
    }
    _last = now;
    final map = {
      for (final p in points)
        if (p.confidence >= .65 &&
            p.confidence <= 1 &&
            p.x.isFinite &&
            p.y.isFinite &&
            p.x >= .04 &&
            p.x <= .96 &&
            p.y >= .04 &&
            p.y <= .96)
          p.id: p
    };
    visible = map.containsKey(KeypointId.nose) &&
        const [
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
          ]
        ].any((side) => side.every(map.containsKey));
    final pose =
        const PrayerPoseClassifier().classify(points, aspectRatio: aspect).pose;
    final expected =
        phase == FloorCheckPhase.ruku ? PrayerPose.ruku : PrayerPose.sujood;
    if (!visible || pose != expected) {
      _since = null;
      _frames = 0;
      return;
    }
    _since ??= now;
    _frames++;
    if (_frames >= 4 &&
        now.difference(_since!) >= const Duration(milliseconds: 800)) {
      phase = phase == FloorCheckPhase.ruku
          ? FloorCheckPhase.sujood
          : FloorCheckPhase.completed;
      _since = null;
      _frames = 0;
    }
  }
}
