// ─────────────────────────────────────────────────────────────────────────────
// keypoint.dart
//
// Skeleton keypoint model + bone graph.
//
// We standardize on the 17-point COCO skeleton (MoveNet / BlazePose both
// emit a superset). Using IDs instead of indexes keeps the code readable
// — `KeypointId.leftKnee` is easier to reason about than `keypoints[13]`.
// ─────────────────────────────────────────────────────────────────────────────

/// Logical joint identifier.
enum KeypointId {
  nose,
  leftEye,
  rightEye,
  leftEar,
  rightEar,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  // Not part of the 17-point COCO set, but computed client-side as the
  // midpoint between shoulders and hips for the AR overlay.
  spineMid,
}

/// A single detected joint.
///
/// Coordinates are in the *normalized image space* (0..1 in both axes)
/// irrespective of display size. The overlay widget multiplies by its own
/// paint size, so pose detectors can feed us their native output directly.
class Keypoint {
  const Keypoint({
    required this.id,
    required this.x,
    required this.y,
    required this.confidence,
    this.position3d,
  });

  final KeypointId id;
  final double x; // 0..1 from image left.
  final double y; // 0..1 from image top.
  final double confidence; // 0..1.
  /// Providers must preserve their coordinate space; ML Kit depth is not metric 3D.
  final PosePoint3d? position3d;

  /// Cheap immutability helper for the pose detector stubs, which animate a
  /// canned skeleton by perturbing a few coordinates per frame.
  Keypoint copyWith(
      {double? x, double? y, double? confidence, PosePoint3d? position3d}) {
    return Keypoint(
      id: id,
      x: x ?? this.x,
      y: y ?? this.y,
      confidence: confidence ?? this.confidence,
      position3d: position3d ?? this.position3d,
    );
  }
}

enum Pose3dSpace { mediapipeWorldMeters, mlkitImagePixels }

class PosePoint3d {
  const PosePoint3d(this.x, this.y, this.z, this.space);
  final double x, y, z;
  final Pose3dSpace space;
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;
}

/// The bone graph — pairs of [KeypointId]s to connect with line segments in
/// the AR overlay. Order within a pair doesn't matter; we just need every
/// structural bone listed once.
const List<(KeypointId, KeypointId)> skeletonBones = [
  // Head.
  (KeypointId.leftEye, KeypointId.rightEye),
  (KeypointId.leftEye, KeypointId.nose),
  (KeypointId.rightEye, KeypointId.nose),
  // Torso.
  (KeypointId.leftShoulder, KeypointId.rightShoulder),
  (KeypointId.leftShoulder, KeypointId.leftHip),
  (KeypointId.rightShoulder, KeypointId.rightHip),
  (KeypointId.leftHip, KeypointId.rightHip),
  // Spine midpoint — purely for visual affordance when we flag a curved back.
  (KeypointId.leftShoulder, KeypointId.spineMid),
  (KeypointId.rightShoulder, KeypointId.spineMid),
  (KeypointId.spineMid, KeypointId.leftHip),
  (KeypointId.spineMid, KeypointId.rightHip),
  // Arms.
  (KeypointId.leftShoulder, KeypointId.leftElbow),
  (KeypointId.leftElbow, KeypointId.leftWrist),
  (KeypointId.rightShoulder, KeypointId.rightElbow),
  (KeypointId.rightElbow, KeypointId.rightWrist),
  // Legs.
  (KeypointId.leftHip, KeypointId.leftKnee),
  (KeypointId.leftKnee, KeypointId.leftAnkle),
  (KeypointId.rightHip, KeypointId.rightKnee),
  (KeypointId.rightKnee, KeypointId.rightAnkle),
];

/// Symbolic joint names carried in pose events. These match the strings the
/// backend `schemas.py` recognizes, so any new faulty-joint label added here
/// must also be handled by the prompt template server-side.
class JointTag {
  const JointTag._();

  static const String spineMid = 'spine_mid';
  static const String leftKnee = 'left_knee';
  static const String rightKnee = 'right_knee';
  static const String leftHip = 'left_hip';
  static const String rightHip = 'right_hip';
}
