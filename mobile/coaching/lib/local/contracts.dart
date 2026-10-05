import 'dart:typed_data';

const localConfiguration = <String, dynamic>{
  'inference_provider': 'local',
  'mock_enabled': false,
  'live_enabled': true,
  'live_modes': ['buffered', 'adaptive'],
  'frame_sample_fps': 4.0,
  'max_duration_ms': 1200000,
  'max_frames': 2400,
  'batch_frames': 1,
  'max_dimension': 960,
  'max_frame_bytes': 200000,
  'live_buffer_bytes': 64000000,
  'max_evidence_bytes': 64000000,
};
const predictionSchema = '2.0.0';
const modelSeeds = ['2026', '3407', '8111'];
const actionClasses = [
  '1_Qiyam',
  '2_Takbir',
  '3_Qiyam_Recitation',
  '4_Ruku',
  '5_Sujud',
  '6_Jalsa',
  '7_Salam_Right',
  '8_Salam_Left'
];
const actionPoses = [
  'standing',
  'takbir',
  'standing',
  'ruku',
  'sujood',
  'sitting',
  'salam_right',
  'salam_left'
];
const actionArabic = [
  'القيام',
  'التكبير',
  'القيام والقراءة',
  'الركوع',
  'السجود',
  'الجلسة',
  'التسليم يمينًا',
  'التسليم يسارًا'
];

bool validPrediction(Map<String, dynamic> r, String version) {
  if (r['schema_version'] != predictionSchema ||
      r['model_version'] != version) {
    return false;
  }
  final duration = r['inference_ms'], models = r['individual_models'];
  if (duration is! num ||
      !duration.isFinite ||
      duration < 0 ||
      models is! List ||
      models.length != 3) {
    return false;
  }
  for (var i = 0; i < 3; i++) {
    if (models[i] is! Map || models[i]['seed'] != modelSeeds[i]) return false;
  }
  bool empty(Map m) =>
      m['predicted_action'] == null &&
      m['class_index'] == null &&
      m['confidence'] == 0 &&
      m['probabilities'] is Map &&
      (m['probabilities'] as Map).isEmpty &&
      m['top3'] is List &&
      (m['top3'] as List).isEmpty;
  if (r['pose_detected'] != true) {
    return r['normalization_valid'] == false &&
        empty(r) &&
        models.every((m) => m['available'] == false && empty(m));
  }
  if (r['normalization_valid'] != true) return false;
  List<double>? probabilities(Map m) {
    final p = m['probabilities'];
    if (p is! Map || p.length != 8) return null;
    final values = <double>[];
    for (final c in actionClasses) {
      final v = p[c];
      if (v is! num || !v.isFinite || v < 0 || v > 1) return null;
      values.add(v.toDouble());
    }
    if ((values.fold<double>(0, (a, b) => a + b) - 1).abs() > 1e-5) return null;
    return values;
  }

  bool complete(Map m, List<double> p) {
    final order = List.generate(8, (i) => i)
      ..sort((a, b) {
        final difference = p[b].compareTo(p[a]);
        return difference == 0 ? b.compareTo(a) : difference;
      });
    final winner = order.first, c = m['confidence'], top = m['top3'];
    if (m['class_index'] != winner ||
        m['predicted_action'] != actionClasses[winner] ||
        c is! num ||
        !c.isFinite ||
        (c - p[winner]).abs() > 1e-6 ||
        top is! List ||
        top.length != 3) {
      return false;
    }
    for (var i = 0; i < 3; i++) {
      final item = top[i];
      if (item is! Map || item['action'] != actionClasses[order[i]]) {
        return false;
      }
      final v = item['probability'];
      if (v is! num || !v.isFinite || (v - p[order[i]]).abs() > 1e-6) {
        return false;
      }
    }
    return true;
  }

  final arrays = <List<double>>[];
  for (final m in models) {
    final p = probabilities(m);
    if (p == null || !complete(m, p)) return false;
    arrays.add(p);
  }
  final average =
      List.generate(8, (i) => (arrays[0][i] + arrays[1][i] + arrays[2][i]) / 3);
  final ensemble = probabilities(r);
  return ensemble != null &&
      complete(r, average) &&
      List.generate(8, (i) => i)
          .every((i) => (ensemble[i] - average[i]).abs() <= 1e-6);
}

class LocalFrameResult {
  LocalFrameResult(this.result,
      {this.preview, this.previewLoader, this.landmarks = const []});
  final Map<String, dynamic> result;
  final List<Map<String, dynamic>> landmarks;
  final Uint8List? preview;
  final Future<Uint8List?> Function()? previewLoader;
  Future<Uint8List?> loadPreview() async =>
      preview ?? await previewLoader?.call();
}

abstract interface class InitializationProgressSource {
  Map<String, dynamic> get initializationProgress;
}

abstract interface class LocalInference {
  Future<Map<String, dynamic>> initialize();
  Future<LocalFrameResult> analyze(Uint8List jpeg);
  Future<Map<String, dynamic>> report(String prayer,
      List<Map<String, dynamic>> samples, Map<String, dynamic> options);
  Future<void> close();
}

abstract interface class LocalSessionRepository {
  Future<void> save(
      Map<String, dynamic> metadata, Map<String, Uint8List> evidence);
  Future<List<Map<String, dynamic>>> list();
  Future<Map<String, dynamic>?> load(String id);
  Future<Uint8List> evidence(String sessionId, String evidenceId);
  Future<void> delete(String id);
  Future<String> export(String id);
}
