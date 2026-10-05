import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/keypoint.dart';
import 'prayer_definition.dart';

const referenceStationKeys = [
  'standing',
  'ruku',
  'standing_after_ruku',
  'sujood_first',
  'sitting',
  'sujood_second'
];

class ReferenceSegment {
  ReferenceSegment(this.station, this.preview, this.aspectRatio, this.samples);
  final PrayerStation station;
  final List<Keypoint> preview;
  final double aspectRatio;
  final List<Map<KeypointId, (double, double)>> samples;
}

class PrayerReference {
  PrayerReference(this.id, this.name, this.revision, this.view, this.segments,
      {Map<String, dynamic>? sourceJson})
      : _sourceJson = sourceJson == null
            ? null
            : jsonDecode(jsonEncode(sourceJson)) as Map<String, dynamic>;
  final String id, name, view;
  final int revision;
  final List<ReferenceSegment> segments;
  final Map<String, dynamic>? _sourceJson;
  ReferenceSegment get standing => segments.first;

  /// Preserve the imported authoring metadata and evidence without conversion.
  Map<String, dynamic> toJson() {
    if (_sourceJson == null) {
      throw StateError('هذا المرجع لا يحتوي على ملف الاستيراد الأصلي.');
    }
    return jsonDecode(jsonEncode(_sourceJson)) as Map<String, dynamic>;
  }

  factory PrayerReference.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 2 ||
        json['world_coordinate_space'] != 'mediapipe_world_meters') {
      throw const FormatException(
          'استورد مرجعًا محليًا متوافقًا مع الإصدار 2 وبيانات الضبط.');
    }
    if (json['id'] is! String ||
        (json['id'] as String).trim().isEmpty ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty ||
        (json['name'] as String).length > 200 ||
        json['revision'] is! int ||
        (json['revision'] as int) < 1 ||
        json['view'] is! String) {
      throw const FormatException('بيانات تعريف المرجع غير صالحة.');
    }
    final rawSegments = json['segments'] as List<dynamic>;
    if (rawSegments.length != 6) {
      throw const FormatException('المرجع غير مكتمل.');
    }
    final segments = <ReferenceSegment>[];
    for (var i = 0; i < rawSegments.length; i++) {
      final raw = rawSegments[i] as Map<String, dynamic>;
      if (raw['station'] != referenceStationKeys[i]) {
        throw const FormatException('ترتيب المرجع غير صالح.');
      }
      final aspect = (raw['image_aspect_ratio'] as num).toDouble();
      if (!aspect.isFinite || aspect <= 0 || aspect > 10) {
        throw const FormatException('أبعاد المرجع غير صالحة.');
      }
      final samples = <Map<KeypointId, (double, double)>>[];
      for (final sample in raw['samples'] as List<dynamic>) {
        final joints =
            (sample as Map<String, dynamic>)['joints'] as Map<String, dynamic>;
        final mapped = <KeypointId, (double, double)>{};
        for (final entry in joints.entries) {
          final id = _id(entry.key);
          if (id == null) continue;
          final p = entry.value as Map<String, dynamic>;
          final x = (p['x'] as num).toDouble(), y = (p['y'] as num).toDouble();
          if (!x.isFinite || !y.isFinite) {
            throw const FormatException('نقاط المرجع غير صالحة.');
          }
          mapped[id] = (x, y);
        }
        if (mapped.length >= 4) samples.add(Map.unmodifiable(mapped));
      }
      final preview = <Keypoint>[];
      for (final value in raw['representative_keypoints'] as List<dynamic>) {
        final p = value as Map<String, dynamic>;
        final id = _id(p['id'] as String);
        if (id == null) continue;
        final x = (p['x'] as num).toDouble(), y = (p['y'] as num).toDouble();
        final confidence = (p['confidence'] as num).toDouble();
        if (!x.isFinite ||
            !y.isFinite ||
            !confidence.isFinite ||
            confidence < 0 ||
            confidence > 1) {
          throw const FormatException('الصورة الممثلة غير صالحة.');
        }
        preview.add(Keypoint(id: id, x: x, y: y, confidence: confidence));
      }
      if (samples.length < 3 || preview.isEmpty) {
        throw const FormatException('أدلة المرجع غير كافية.');
      }
      segments.add(ReferenceSegment(PrayerStation.values[i],
          List.unmodifiable(preview), aspect, List.unmodifiable(samples)));
    }
    return PrayerReference(
        json['id'] as String,
        json['name'] as String,
        json['revision'] as int,
        json['view'] as String,
        List.unmodifiable(segments),
        sourceJson: json);
  }

  static KeypointId? _id(String name) {
    for (final id in KeypointId.values) {
      if (id.name == name) return id;
    }
    return null;
  }
}

class PrayerReferenceRepository {
  PrayerReferenceRepository({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;
  Future<PrayerReference> load(String baseUrl) async {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        !['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const FormatException(
          'أدخل عنوان backend صالحًا يبدأ بـ http أو https.');
    }
    final response = await _client
        .get(base.resolve('/api/v1/prayer-reference'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      throw const FormatException(
          'لا يوجد مرجع مفعّل. ارفع فيديو الصلاة وفعّله في صفحة backend.');
    }
    if (response.statusCode != 200) {
      throw const FormatException('تعذر تحميل المرجع من الخادم.');
    }
    return PrayerReference.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
  }

  void close() => _client.close();
}

/// Compare only common 2D joints. Experimental ML Kit depth is never mixed with world meters.
class PrayerReferenceMatcher {
  PrayerReferenceMatcher(this.reference);
  final PrayerReference reference;
  double distance(List<Keypoint> points, PrayerStation station,
      {double aspectRatio = 1}) {
    final segment = reference.segments[station.isCore
        ? station.index
        : PrayerStation.sittingBetweenSujood.index];
    final visible = {
      for (final p in points)
        if (p.confidence >= .65 &&
            p.confidence <= 1 &&
            p.x.isFinite &&
            p.y.isFinite &&
            p.x >= 0 &&
            p.x <= 1 &&
            p.y >= 0 &&
            p.y <= 1)
          p.id: p
    };
    var best = double.infinity;
    for (final side in const [
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
    ]) {
      if (!side.every(visible.containsKey)) continue;
      final shoulder = visible[side[0]]!, hip = visible[side[1]]!;
      final scale = math.sqrt(math.pow((shoulder.x - hip.x) * aspectRatio, 2) +
          math.pow(shoulder.y - hip.y, 2));
      if (scale < .04) continue;
      for (final sample in segment.samples) {
        if (!side.every(sample.containsKey)) continue;
        // Origin/scale are selected consistently with the backend: its first visible side.
        final origin = sample[side[1]]!;
        final s = sample[side[0]]!;
        final sampleScale = math.sqrt(
            math.pow((s.$1 - origin.$1) * segment.aspectRatio, 2) +
                math.pow(s.$2 - origin.$2, 2));
        if (sampleScale < .001) continue;
        var total = 0.0;
        for (final id in side) {
          final p = visible[id]!, q = sample[id]!;
          total += math
                  .pow(
                      (p.x - hip.x) * aspectRatio / scale -
                          (q.$1 - origin.$1) *
                              segment.aspectRatio /
                              sampleScale,
                      2)
                  .toDouble() +
              math
                  .pow((p.y - hip.y) / scale - (q.$2 - origin.$2) / sampleScale,
                      2)
                  .toDouble();
        }
        best = math.min(best, math.sqrt(total / side.length));
      }
    }
    return best;
  }
}
