import 'dart:convert';
import 'dart:io';

import 'package:coaching/local/contracts.dart';
import 'package:coaching/local/report_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _version = 'local-test';

Map<String, dynamic> _decision(List<double> probabilities) {
  final order = List.generate(8, (i) => i)
    ..sort((a, b) {
      final byProbability = probabilities[b].compareTo(probabilities[a]);
      return byProbability != 0 ? byProbability : b.compareTo(a);
    });
  return {
    'predicted_action': actionClasses[order.first],
    'class_index': order.first,
    'confidence': probabilities[order.first],
    'probabilities': {
      for (var i = 0; i < 8; i++) actionClasses[i]: probabilities[i],
    },
    'top3': [
      for (final i in order.take(3))
        {'action': actionClasses[i], 'probability': probabilities[i]},
    ],
  };
}

// Python temporal fixtures contain minimal observations, not model tensors.
// Add a valid three-model container without changing their measured decisions.
Map<String, dynamic> _complete(Map<String, dynamic> observation) {
  final context = {
    'schema_version': predictionSchema,
    'model_version': _version,
    'inference_ms': 10.0,
    'pose_detected': observation['pose_detected'],
    'normalization_valid': observation['pose_detected'],
  };
  if (observation['pose_detected'] != true) {
    final empty = {
      'predicted_action': null,
      'class_index': null,
      'confidence': 0.0,
      'probabilities': <String, double>{},
      'top3': <Object>[],
    };
    return {
      ...context,
      ...empty,
      'individual_models': [
        for (final seed in modelSeeds)
          {...empty, 'seed': seed, 'available': false},
      ],
    };
  }
  final classIndex = actionClasses.indexOf(observation['predicted_action']);
  final confidence = (observation['confidence'] as num).toDouble();
  final decision = _decision(List.generate(
      8, (i) => i == classIndex ? confidence : (1 - confidence) / 7));
  return {
    ...context,
    ...decision,
    'individual_models': [
      for (final seed in modelSeeds) {...decision, 'seed': seed},
    ],
    'classifier_disagreement': false,
  };
}

Map<String, dynamic> _core(Map<String, dynamic> report) {
  Map<String, dynamic> withoutEvidence(Map raw) => {
        for (final entry in raw.entries)
          if (entry.key != 'evidence_id') entry.key as String: entry.value,
      };
  return {
    'expected_rakahs': report['expected_rakahs'],
    'observed_rakahs': report['observed_rakahs'],
    'overall_result': report['overall_result'],
    'rakahs': [
      for (final row in report['rakahs'] as List)
        {
          ...Map<String, dynamic>.from(row as Map),
          'stations': [
            for (final station in row['stations'] as List)
              withoutEvidence(station as Map),
          ],
        },
    ],
    'events': [
      for (final event in report['events'] as List)
        withoutEvidence(event as Map),
    ],
    'unexpected_movements': [
      for (final event in report['unexpected_movements'] as List)
        withoutEvidence(event as Map),
    ],
    'metrics': {
      for (final name in [
        'detected_stations',
        'unconfirmed_stations',
        'unexpected_movements',
        'processed_frames',
        'sample_fps',
      ])
        name: report['metrics'][name],
    },
  };
}

void _close(Object? actual, Object? expected, String path) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: path);
    final map = actual as Map;
    expect(map.keys.toSet(), expected.keys.toSet(), reason: path);
    for (final key in expected.keys) {
      _close(map[key], expected[key], '$path.$key');
    }
  } else if (expected is List) {
    expect(actual, isA<List>(), reason: path);
    final list = actual as List;
    expect(list.length, expected.length, reason: path);
    for (var i = 0; i < expected.length; i++) {
      _close(list[i], expected[i], '$path[$i]');
    }
  } else if (expected is num) {
    expect(actual, closeTo(expected, 1e-12), reason: path);
  } else {
    expect(actual, expected, reason: path);
  }
}

void main() {
  test(
      '72 native reports match Python temporal, alignment and review placement',
      () {
    final fixtures = jsonDecode(
            File('browser/test/fixtures/local_report.json').readAsStringSync())
        as List;
    expect(fixtures, hasLength(72));
    expect(fixtures.map((f) => f['prayer']).toSet(), prayerCounts.keys.toSet());
    for (var i = 0; i < fixtures.length; i++) {
      final fixture = fixtures[i] as Map;
      final samples = [
        for (final raw in fixture['samples'] as List)
          {
            ...Map<String, dynamic>.from(raw as Map),
            'result':
                _complete(Map<String, dynamic>.from(raw['result'] as Map)),
          },
      ];
      final actual = buildLocalReport(fixture['prayer'] as String, samples,
          {'analysis_id': 'fixture', 'model_version': _version});
      _close(
          _core(actual),
          _core(Map<String, dynamic>.from(fixture['expected'])),
          'Python fixture $i (${fixture['prayer']})');
      expect(actual['analysis_mode'], 'local');
      expect(actual['synthetic'], isFalse);
      expect(actual['prediction_schema_version'], '2.0.0');
      for (final event in actual['events'] as List) {
        expect(event['evidence_id'], event['representative_frame_id']);
      }
      for (final prediction in (actual['predictions'] as Map).values) {
        expect(prediction['individual_models'], hasLength(3));
      }
    }
  });

  test('temporal sorting, defaults, thresholds, stable duration and ties match',
      () {
    Map<String, dynamic> sample(int index, {double confidence = .95}) => {
          'frame_id': 'frame_$index',
          'timestamp_ms': index * 250,
          'sequence_index': index,
          'result': _complete({
            'pose_detected': true,
            'predicted_action': actionClasses[3],
            'confidence': confidence,
          }),
        };
    final first = sample(0), second = sample(1), third = sample(2);
    final events = localTemporal([third, second, first]);
    expect(events, hasLength(1));
    expect(events.single['representative_frame_id'], 'frame_0');
    expect(events.single['candidate_timestamp_ms'], 0);
    expect(
        localTemporal([first], minObservations: 2).single['pose'], 'unknown');
    expect(localTemporal([first, second], minDurationMs: 251).single['pose'],
        'unknown');
    expect(localTemporal([first, second], minDurationMs: 250).single['pose'],
        'ruku');
    expect(localTemporal([sample(0, confidence: .65)]).single['pose'], 'ruku');
    expect(
        localTemporal([sample(0, confidence: .65)], threshold: .66)
            .single['pose'],
        'unknown');
    final defaultIndex = {...first}..remove('sequence_index');
    expect(localTemporal([defaultIndex]).single['pose'], 'ruku');
    expect(
        () => localTemporal([
              first,
              {...second, 'sequence_index': 0}
            ]),
        throwsStateError);
    expect(
        () => localTemporal([
              first,
              {...second, 'timestamp_ms': 0}
            ]),
        throwsStateError);
  });

  test(
      'report input schema, frame identity and timestamp validation fail closed',
      () {
    final sample = <String, dynamic>{
      'frame_id': 'frame_0',
      'timestamp_ms': 0,
      'sequence_index': 0,
      'result': _complete({
        'pose_detected': true,
        'predicted_action': actionClasses[3],
        'confidence': .95,
      }),
    };
    expect(() => buildLocalReport('demo', [], {}), throwsStateError);
    expect(
        () => buildLocalReport('demo', [sample, sample], {}), throwsStateError);
    expect(
        () => buildLocalReport('demo', [
              {...sample, 'frame_id': '../x'}
            ], {}),
        throwsStateError);
    expect(
        () => buildLocalReport('demo', [
              {...sample, 'timestamp_ms': -1}
            ], {}),
        throwsStateError);
    final incomplete = {
      ...sample,
      'result': {...sample['result'], 'individual_models': []},
    };
    expect(() => buildLocalReport('demo', [incomplete], {}), throwsStateError);
    expect(() => buildLocalReport('demo', List.filled(2401, sample), {}),
        throwsStateError);
  });
}
