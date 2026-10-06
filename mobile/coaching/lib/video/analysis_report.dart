// Presentation contract shared by local processing and legacy HTTP tooling.
class AnalysisReport {
  AnalysisReport.fromJson(Map<String, dynamic> json)
      : raw = Map<String, dynamic>.from(json),
        prayer = json['prayer'] as String,
        expectedRakahs = json['expected_rakahs'] as int,
        observedRakahs = json['observed_rakahs'] as int,
        synthetic = json['synthetic'] as bool,
        notice = json['notice'] as String,
        overallResult = json['overall_result'] as String,
        rakahs = (json['rakahs'] as List)
            .map((r) => RakahReport.fromJson(r))
            .toList(),
        unexpected = (json['unexpected_movements'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        events = (json['events'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList() {
    if (json['schema_version'] != '1.0' ||
        json['status'] != 'COMPLETED' ||
        (json['analysis_mode'] == 'mock') != synthetic) {
      throw const FormatException('Unsupported analysis report');
    }
  }
  final String prayer, notice, overallResult;
  final Map<String, dynamic> raw;
  Map<String, dynamic>? prediction(String? frameId) {
    final value = (raw['predictions'] as Map?)?[frameId];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  String? get storageWarning => raw['storage_warning'] as String?;
  List<Map<String, dynamic>> get capturedActions =>
      (raw['captured_actions'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  /// Coverage of expected report stations, never a posture or validity verdict.
  int get movementsExpected =>
      rakahs.fold(0, (sum, rakah) => sum + rakah.stations.length);
  int get movementsDetected => rakahs.fold(
      0,
      (sum, rakah) =>
          sum + rakah.stations.where((s) => s.status == 'DETECTED').length);
  double get movementScore => movementsExpected == 0
      ? 0
      : (10000 * movementsDetected / movementsExpected).round() / 100;
  Map<String, dynamic> get movementSummary => {
        'movements_detected': movementsDetected,
        'movements_expected': movementsExpected,
        'movement_score': movementScore,
      };
  final int expectedRakahs, observedRakahs;
  final bool synthetic;
  final List<RakahReport> rakahs;
  final List<Map<String, dynamic>> unexpected, events;
}

class RakahReport {
  RakahReport.fromJson(Map<String, dynamic> json)
      : number = json['rakah_number'] as int,
        result = json['result'] as String,
        notes = List<String>.from(json['notes']),
        stations = (json['stations'] as List)
            .map((s) => StationReport.fromJson(s))
            .toList();
  final int number;
  final String result;
  final List<String> notes;
  final List<StationReport> stations;
}

class StationReport {
  StationReport.fromJson(Map<String, dynamic> json)
      : key = json['station'] as String,
        label = json['arabic_label'] as String,
        status = json['status'] as String,
        confidence = (json['confidence'] as num?)?.toDouble(),
        timestampMs = json['timestamp_ms'] as int?,
        evidenceId = json['evidence_id'] as String?;
  final String key, label, status;
  final double? confidence;
  final int? timestampMs;
  final String? evidenceId;
}
