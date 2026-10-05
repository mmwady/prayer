import 'package:coaching/models/keypoint.dart';
import 'package:coaching/prayer/prayer_reference.dart';

List<Keypoint> calibrationPoints(
        {double shoulderSpread = .20,
        double hipSpread = .14,
        double noseX = .5}) =>
    [
      Keypoint(id: KeypointId.nose, x: noseX, y: .15, confidence: .95),
      for (final side in [true, false]) ...[
        Keypoint(
            id: side ? KeypointId.leftShoulder : KeypointId.rightShoulder,
            x: .5 + (side ? -1 : 1) * shoulderSpread / 2,
            y: .25,
            confidence: .95),
        Keypoint(
            id: side ? KeypointId.leftHip : KeypointId.rightHip,
            x: .5 + (side ? -1 : 1) * hipSpread / 2,
            y: .5,
            confidence: .95),
        Keypoint(
            id: side ? KeypointId.leftKnee : KeypointId.rightKnee,
            x: .5 + (side ? -1 : 1) * hipSpread / 2,
            y: .70,
            confidence: .95),
        Keypoint(
            id: side ? KeypointId.leftAnkle : KeypointId.rightAnkle,
            x: .5 + (side ? -1 : 1) * hipSpread / 2,
            y: .87,
            confidence: .95),
      ],
    ];

Map<String, dynamic> referenceFixture({List<Keypoint>? points}) {
  final p = points ?? calibrationPoints();
  final hip = p.firstWhere((p) => p.id == KeypointId.leftHip);
  final normalized = {
    for (final point in p)
      point.id.name: {
        'x': (point.x - hip.x) / .25,
        'y': (point.y - hip.y) / .25
      }
  };
  return {
    'id': 'test-reference',
    'name': 'مرجع اختبار اصطناعي',
    'revision': 1,
    'schema_version': 2,
    'view': 'front',
    'world_coordinate_space': 'mediapipe_world_meters',
    'segments': [
      for (final station in referenceStationKeys)
        {
          'station': station,
          'image_aspect_ratio': 1,
          'representative_keypoints': p
              .map((p) => {
                    'id': p.id.name,
                    'x': p.x,
                    'y': p.y,
                    'confidence': p.confidence
                  })
              .toList(),
          'samples': [
            for (var i = 0; i < 3; i++) {'joints': normalized}
          ]
        },
    ]
  };
}

PrayerReference calibrationReference() =>
    PrayerReference.fromJson(referenceFixture());
