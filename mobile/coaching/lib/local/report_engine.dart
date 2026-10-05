// Conservative all-optimal-path sequence alignment, ported from the existing
// Python validator. Classification confidence never denotes prayer validity.
import 'dart:typed_data';
import 'contracts.dart';
import 'assessment_options.dart';
import 'sequence_normalization.dart';

const prayerCounts = {
  'fajr': 2,
  'dhuhr': 4,
  'asr': 4,
  'maghrib': 3,
  'isha': 4,
  'demo': 1
};
const stationLabels = {
  'standing': 'القيام',
  'takbir': 'تكبيرة الإحرام',
  'ruku': 'الركوع',
  'standing_after_ruku': 'الاعتدال بعد الركوع',
  'sujood_first': 'السجود الأول',
  'sitting': 'الجلوس بين السجدتين',
  'sujood_second': 'السجود الثاني',
  'intermediate_sitting': 'الجلوس الأوسط',
  'final_sitting': 'الجلوس الأخير',
  'salam_right': 'السلام يمينًا',
  'salam_left': 'السلام يسارًا'
};
String stationPose(String s) => switch (s) {
      'standing_after_ruku' => 'standing',
      'sujood_first' || 'sujood_second' => 'sujood',
      'intermediate_sitting' || 'final_sitting' => 'sitting',
      _ => s
    };
String resultPose(Map<String, dynamic> r) {
  final i = actionClasses.indexOf(r['predicted_action'] ?? '');
  return i < 0 ? 'unknown' : actionPoses[i];
}

List<List<String>> reportStations(String prayer) {
  final count = prayerCounts[prayer];
  if (count == null) throw ArgumentError('Unknown prayer');
  return List.generate(
      count,
      (i) => [
            if (i == 0) 'takbir',
            'standing',
            'ruku',
            'standing_after_ruku',
            'sujood_first',
            'sitting',
            'sujood_second',
            if (i == 1 && count > 2) 'intermediate_sitting',
            if (i == count - 1) ...[
              'final_sitting',
              'salam_right',
              'salam_left'
            ]
          ]);
}

bool _valid(Map<String, dynamic> s, double threshold) =>
    _decision(s)['pose_detected'] == true &&
    (_decision(s)['confidence'] as num) >= threshold &&
    resultPose(_decision(s)) != 'unknown';
Map<String, dynamic> _decision(Map<String, dynamic> s) =>
    Map<String, dynamic>.from((s['assessment'] ?? s['result']) as Map);
List<Map<String, dynamic>> localTemporal(List<Map<String, dynamic>> samples,
    {double threshold = .65,
    int minObservations = 1,
    int minDurationMs = 0,
    int maxGapMs = 1000}) {
  samples = [
    for (var i = 0; i < samples.length; i++)
      <String, dynamic>{'sequence_index': i, ...samples[i]}
  ]..sort(
      (a, b) => (a['timestamp_ms'] as int).compareTo(b['timestamp_ms'] as int));
  final groups = <List<Map<String, dynamic>>>[],
      events = <Map<String, dynamic>>[];
  for (var i = 0; i < samples.length; i++) {
    final item = samples[i];
    if (i > 0 &&
        ((item['timestamp_ms'] as int) <=
                (samples[i - 1]['timestamp_ms'] as int) ||
            (item['sequence_index'] as int) <=
                (samples[i - 1]['sequence_index'] as int))) {
      throw StateError('INVALID_TIMESTAMP_ORDER');
    }
    final prev = groups.isEmpty ? null : groups.last.last;
    if (prev != null) {
      if ((item['timestamp_ms'] as int) - (prev['timestamp_ms'] as int) >
          maxGapMs) {
        events.add({
          'pose': 'unknown',
          'start_ms': prev['timestamp_ms'],
          'end_ms': item['timestamp_ms'],
          'confidence': 0.0,
          'observation_status': 'uncertain',
          'candidate_pose': null,
          'candidate_confidence': null,
          'candidate_timestamp_ms': null,
          'representative_frame_id': null,
          'evidence_id': null
        });
      } else if (_valid(item, threshold) == _valid(prev, threshold) &&
          (!_valid(item, threshold) ||
              resultPose(_decision(item)) == resultPose(_decision(prev)))) {
        groups.last.add(item);
        continue;
      }
    }
    groups.add([item]);
  }
  for (final group in groups) {
    final stable = _valid(group.first, threshold) &&
        group.length >= minObservations &&
        (group.last['timestamp_ms'] as int) -
                (group.first['timestamp_ms'] as int) >=
            minDurationMs;
    Map<String, dynamic>? best;
    for (final s in group) {
      if ((stable ||
              (_decision(s)['pose_detected'] == true &&
                  resultPose(_decision(s)) != 'unknown')) &&
          (best == null ||
              (_decision(s)['confidence'] as num) >
                  (_decision(best)['confidence'] as num))) {
        best = s;
      }
    }
    events.add({
      'pose': stable ? resultPose(_decision(group.first)) : 'unknown',
      'start_ms': group.first['timestamp_ms'],
      'end_ms': group.last['timestamp_ms'],
      'confidence': group.fold<double>(
              0,
              (sum, s) =>
                  sum + (_decision(s)['confidence'] as num).toDouble()) /
          group.length,
      'candidate_pose': best == null ? null : resultPose(_decision(best)),
      'candidate_confidence':
          best == null ? null : _decision(best)['confidence'],
      'candidate_timestamp_ms': best?['timestamp_ms'],
      'representative_frame_id': best?['frame_id'],
      'evidence_id': best?['frame_id'],
      'observation_status': stable ? 'detected' : 'uncertain'
    });
  }
  events.sort((a, b) {
    final c = (a['start_ms'] as int).compareTo(b['start_ms'] as int);
    return c != 0 ? c : (a['end_ms'] as int).compareTo(b['end_ms'] as int);
  });
  return events.indexed
      .map((e) =>
          {...e.$2, 'event_id': 'evt_${e.$1.toString().padLeft(4, '0')}'})
      .toList();
}

Map<String, dynamic> localSequence(
    String prayer, List<Map<String, dynamic>> events,
    {bool normalizeSequence = false}) {
  final rows = reportStations(prayer),
      expected = [
        for (var r = 0; r < rows.length; r++)
          for (final s in rows[r]) {'station': s, 'r': r}
      ];
  final detected = normalizeSequence
      ? normalizeLocalEvents(events)
      : events.where((e) => e['observation_status'] == 'detected').toList();
  final n = detected.length, m = expected.length;
  final prefix = List.generate(n + 1, (_) => Int32List(m + 1)),
      suffix = List.generate(n + 1, (_) => Int32List(m + 1));
  bool matches(int i, int j) =>
      detected[i]['pose'] == stationPose(expected[j]['station'] as String);
  int max3(int a, int b, int c) => a > b ? (a > c ? a : c) : (b > c ? b : c);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < m; j++) {
      prefix[i + 1][j + 1] = max3(prefix[i][j + 1], prefix[i + 1][j],
          prefix[i][j] + (matches(i, j) ? 1 : 0));
    }
  }
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      suffix[i][j] = max3(suffix[i + 1][j], suffix[i][j + 1],
          suffix[i + 1][j + 1] + (matches(i, j) ? 1 : 0));
    }
  }
  final best = suffix[0][0],
      candidates = List.generate(
          m,
          (j) => [
                for (var i = 0; i < n; i++)
                  if (matches(i, j) &&
                      prefix[i][j] + 1 + suffix[i + 1][j + 1] == best)
                    i
              ]);
  final reverse = List.generate(
      n,
      (i) => [
            for (var j = 0; j < m; j++)
              if (candidates[j].contains(i)) j
          ]);
  var confirmed = <int, Map<String, dynamic>>{};
  final used = <int>{};
  for (var j = 0; j < m; j++) {
    final optional = List.generate(n + 1, (i) => i)
        .any((i) => prefix[i][j] + suffix[i][j + 1] == best);
    final options = candidates[j];
    if (options.length == 1 &&
        reverse[options.first].length == 1 &&
        !optional) {
      confirmed[j] = detected[options.first];
      used.add(options.first);
    }
  }
  if (normalizeSequence) {
    used.clear();
    confirmed = normalizedLocalAlignment(rows, detected, stationPose, used);
  }
  var offset = 0;
  final rakahs = rows.indexed.map((row) {
    final stations = row.$2.map((s) {
      final e = confirmed[offset++];
      return <String, dynamic>{
        'station': s,
        'arabic_label': stationLabels[s],
        'status': e != null ? 'DETECTED' : 'UNCONFIRMED',
        if (normalizeSequence) 'assignment_method': 'normalized_sequence',
        'confidence': e?['candidate_confidence'] ?? e?['confidence'],
        'timestamp_ms': e?['candidate_timestamp_ms'] ?? e?['start_ms'],
        'event_id': e?['event_id'],
        'evidence_id': e?['evidence_id']
      };
    }).toList();
    return {
      'rakah_number': row.$1 + 1,
      'result': stations.every((s) => s['status'] == 'DETECTED')
          ? 'OBSERVED_COMPLETE'
          : 'REVIEW_REQUIRED',
      'stations': stations,
      'notes': [
        for (final s in stations)
          if (s['status'] == 'UNCONFIRMED')
            'لم نتمكن من تأكيد ${s['arabic_label']} من الصور المتاحة.'
      ]
    };
  }).toList();
  final unexpected = [
    for (var i = 0; i < n; i++)
      if (!used.contains(i))
        <String, dynamic>{
          'event_id': detected[i]['event_id'],
          'pose': detected[i]['pose'],
          'start_ms': detected[i]['start_ms'],
          'confidence':
              detected[i]['candidate_confidence'] ?? detected[i]['confidence'],
          'timestamp_ms': detected[i]['candidate_timestamp_ms'],
          'evidence_id': detected[i]['evidence_id'],
          'reason': normalizeSequence || reverse[i].isEmpty
              ? 'out_of_sequence_or_repeated'
              : 'ambiguous'
        }
  ];
  // Python's temporal review placement provides context, never confirmation.
  final anchors = [
    for (final entry in confirmed.entries)
      (entry.value['start_ms'] as int, (expected[entry.key]['r'] as int) + 1)
  ]..sort((a, b) {
      final byTime = a.$1.compareTo(b.$1);
      return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
    });
  final boundaries = <(int, int)>[];
  var base = 0;
  for (var r = 0; r < rows.length - 1; r++) {
    if (List.generate(rows[r].length, (j) => base + j)
        .every(confirmed.containsKey)) {
      boundaries
          .add((confirmed[base + rows[r].length - 1]!['end_ms'] as int, r + 2));
    }
    base += rows[r].length;
  }
  for (final item in [...unexpected, ...events]) {
    item['review_rakah_number'] = null;
    item['review_before_station_index'] = null;
    if (anchors.isEmpty) continue;
    final preceding =
        anchors.where((anchor) => anchor.$1 <= (item['start_ms'] as int));
    var number = preceding.isEmpty ? anchors.first.$2 : preceding.last.$2;
    for (final boundary in boundaries) {
      if ((item['start_ms'] as int) > boundary.$1 && boundary.$2 > number) {
        number = boundary.$2;
      }
    }
    final row = rakahs[number - 1]['stations'] as List;
    final slot = row.indexWhere((station) =>
        station['timestamp_ms'] != null &&
        (station['timestamp_ms'] as int) > (item['start_ms'] as int));
    item['review_rakah_number'] = number;
    item['review_before_station_index'] = slot < 0 ? row.length : slot;
  }
  final completed =
      rakahs.where((r) => r['result'] == 'OBSERVED_COMPLETE').length;
  return {
    'prayer': prayer,
    'expected_rakahs': rows.length,
    'observed_rakahs': completed,
    'rakahs': rakahs,
    'events': events,
    'unexpected_movements': unexpected,
    'overall_result': completed == rows.length &&
            unexpected.isEmpty &&
            !events.any((e) => e['observation_status'] == 'uncertain')
        ? 'OBSERVED_COMPLETE'
        : 'REVIEW_REQUIRED',
    'notice': 'تحليل ترتيب الحركات المرصودة على جهازك، دون حكم على صحة الصلاة.',
    'analysis_mode': 'local',
    'synthetic': false
  };
}

Map<String, dynamic> buildLocalReport(String p,
    List<Map<String, dynamic>> samples, Map<String, dynamic> options) {
  if (samples.length > 2400) throw StateError('LOCAL_FRAME_LIMIT');
  final version = options['model_version'] ??
      (samples.isEmpty ? null : samples.first['result']['model_version']);
  if (version is! String || version.isEmpty) {
    throw StateError('MODEL_VERSION_REQUIRED');
  }
  final ids = <String>{};
  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i], id = sample['frame_id'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id) ||
        !ids.add(id)) {
      throw StateError('INVALID_FRAME_ID');
    }
    final time = sample['timestamp_ms'], index = sample['sequence_index'] ?? i;
    if (time is! int || time < 0 || index is! int || index < 0) {
      throw StateError('INVALID_TIMESTAMP_ORDER');
    }
    if (sample['result'] is! Map ||
        !validPrediction(
            Map<String, dynamic>.from(sample['result']), version)) {
      throw StateError(
          'INVALID_PREDICTION_SCHEMA: expected three model decisions');
    }
  }
  final settings = LocalAssessmentOptions.fromMap(options);
  final assessed = [
    for (final s in samples)
      assessLocalSample(s, settings,
          threshold:
              (options['temporal_confidence'] as num?)?.toDouble() ?? .65)
  ];
  final events = localTemporal(assessed,
      threshold: (options['temporal_confidence'] as num?)?.toDouble() ?? .65,
      minObservations: options['min_observations'] as int? ?? 1,
      minDurationMs: options['min_duration_ms'] as int? ?? 0,
      maxGapMs: options['max_gap_ms'] as int? ?? 1000);
  final report = localSequence(p, events,
          normalizeSequence: settings.sequenceNormalization),
      rows = report['rakahs'] as List;
  final rawReport = settings.enabled
      ? localSequence(
          p,
          localTemporal(samples,
              threshold:
                  (options['temporal_confidence'] as num?)?.toDouble() ?? .65,
              minObservations: options['min_observations'] as int? ?? 1,
              minDurationMs: options['min_duration_ms'] as int? ?? 0,
              maxGapMs: options['max_gap_ms'] as int? ?? 1000))
      : null;
  // An optional alignment must not erase uncertainty present in the raw evidence.
  if (rawReport?['overall_result'] == 'REVIEW_REQUIRED') {
    report['overall_result'] = 'REVIEW_REQUIRED';
  }
  final total =
      rows.fold<int>(0, (sum, row) => sum + (row['stations'] as List).length);
  final detected = rows.fold<int>(
      0,
      (sum, row) =>
          sum +
          (row['stations'] as List)
              .where((station) => station['status'] == 'DETECTED')
              .length);
  return {
    ...report,
    'schema_version': '1.0',
    'status': 'COMPLETED',
    'analysis_id': options['analysis_id'] ??
        'local_${DateTime.now().microsecondsSinceEpoch}',
    'model_version': version,
    'prediction_schema_version': predictionSchema,
    'predictions': {for (final s in samples) s['frame_id']: s['result']},
    'assessment_options': settings.toMap(),
    if (rawReport != null) 'raw_assessment': rawReport,
    'corrections': [
      for (final s in assessed)
        if ((s['corrections'] as List).isNotEmpty)
          {
            'frame_id': s['frame_id'],
            'timestamp_ms': s['timestamp_ms'],
            'raw_action': s['result']['predicted_action'],
            'raw_confidence': s['result']['confidence'],
            'assessed_pose': resultPose(_decision(s)),
            'assessed_confidence': _decision(s)['confidence'],
            'reasons': s['corrections'],
          }
    ],
    'metrics': {
      'detected_stations': detected,
      'unconfirmed_stations': total - detected,
      'unexpected_movements': (report['unexpected_movements'] as List).length,
      'processed_frames': samples.length,
      'sample_fps': options['sample_fps'] ?? 4,
      'inference_provider': 'local',
      'model_version': version,
    },
    'uncertainty': {
      'classifier_disagreements': [
        for (final sample in samples)
          if (sample['result']['classifier_disagreement'] == true)
            sample['frame_id']
      ],
      'unavailable_individual_results': [
        for (final sample in samples)
          if (sample['result']['pose_detected'] != true) sample['frame_id']
      ],
      'notice':
          'ثقة التصنيف تخص الحركة المرصودة، ولا تعني صحة الصلاة. اختلاف النماذج محفوظ للمراجعة.',
    },
  };
}
