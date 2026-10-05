import 'dart:math' as math;
import 'contracts.dart';

/// Corrections affect report observations only, never the three model decisions.
class LocalAssessmentOptions {
  const LocalAssessmentOptions(
      {this.sequenceNormalization = false,
      this.rukuGeometryGate = false,
      this.seatedProbabilityProjection = false});
  static const recommended = LocalAssessmentOptions(
      sequenceNormalization: true, rukuGeometryGate: true);
  final bool sequenceNormalization,
      rukuGeometryGate,
      seatedProbabilityProjection;
  bool get enabled =>
      sequenceNormalization || rukuGeometryGate || seatedProbabilityProjection;
  Map<String, dynamic> toMap() => {
        'sequence_normalization': sequenceNormalization,
        'ruku_geometry_gate': rukuGeometryGate,
        'seated_probability_projection': seatedProbabilityProjection,
      };
  factory LocalAssessmentOptions.fromMap(Map<String, dynamic> values) =>
      LocalAssessmentOptions(
          sequenceNormalization: values['sequence_normalization'] == true,
          rukuGeometryGate: values['ruku_geometry_gate'] == true,
          seatedProbabilityProjection:
              values['seated_probability_projection'] == true);
}

Map<String, dynamic> assessLocalSample(
    Map<String, dynamic> sample, LocalAssessmentOptions options,
    {double threshold = .65}) {
  final raw = Map<String, dynamic>.from(sample['result'] as Map);
  final assessment = Map<String, dynamic>.from(raw), changes = <String>[];
  if (raw['pose_detected'] == true &&
      options.rukuGeometryGate &&
      raw['predicted_action'] == '4_Ruku') {
    final points = sample['landmarks'] as List? ?? const [];
    bool straightLeg(List<int> ids) {
      if (points.length != 33) return false;
      final xy = <List<double>>[];
      for (final i in ids) {
        final point = points[i];
        if (point is! Map ||
            point['x'] is! num ||
            point['y'] is! num ||
            point['visibility'] is! num ||
            !(point['visibility'] as num).isFinite ||
            (point['visibility'] as num) < .5) {
          return false;
        }
        final x = (point['x'] as num).toDouble() * 384,
            y = (point['y'] as num).toDouble() * 512;
        if (!x.isFinite || !y.isFinite) return false;
        xy.add([x, y]);
      }
      final ux = xy[0][0] - xy[1][0],
          uy = xy[0][1] - xy[1][1],
          vx = xy[2][0] - xy[1][0],
          vy = xy[2][1] - xy[1][1];
      final denominator =
          math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy);
      return denominator > 1e-4 &&
          math.acos(((ux * vx + uy * vy) / denominator).clamp(-1.0, 1.0)) *
                  180 /
                  math.pi >=
              160;
    }

    if (!straightLeg([23, 25, 27]) && !straightLeg([24, 26, 28])) {
      assessment['predicted_action'] = 'unknown';
      assessment['confidence'] = 0.0;
      changes.add('ruku_without_straight_leg_evidence');
    }
  }
  if (raw['pose_detected'] == true && options.seatedProbabilityProjection) {
    final probabilities = raw['probabilities'] as Map;
    final seated = ['6_Jalsa', '7_Salam_Right', '8_Salam_Left'].fold<double>(
        0, (sum, name) => sum + (probabilities[name] as num).toDouble());
    if ((assessment['confidence'] as num) < threshold && seated >= threshold) {
      assessment['predicted_action'] = '6_Jalsa';
      assessment['confidence'] = seated;
      changes.add('seated_probability_projection');
    }
  }
  return {...sample, 'assessment': assessment, 'corrections': changes};
}

String correctionLabel(String reason) => switch (reason) {
      'ruku_without_straight_leg_evidence' =>
        'الركوع غير مؤكد: لا توجد أدلة كافية على استقامة الساق',
      'seated_probability_projection' =>
        'ترجيح وضع الجلوس من مجموع احتمالات الجلوس والتسليم',
      _ => reason,
    };

String rawActionLabel(String? action) {
  final index = actionClasses.indexOf(action ?? '');
  return index < 0 ? 'غير مؤكد' : actionArabic[index];
}
