import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:coaching/local/analysis_service.dart';
import 'package:coaching/accounts/sync_adapter.dart';
import 'package:coaching/local/assessment_options.dart';
import 'package:coaching/local/contracts.dart';
import 'package:coaching/local/prediction_cards.dart';
import 'package:coaching/local/report_engine.dart';
import 'package:coaching/local/session.dart';
import 'package:coaching/video/video_source.dart';
import 'package:coaching/screens/video_analysis_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _version = 'test-local-model-v1';

Map<String, dynamic> _clone(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Map<String, dynamic> _decision(List<double> probabilities) {
  final ranked = List.generate(actionClasses.length, (index) => index)
    ..sort((a, b) {
      final comparison = probabilities[b].compareTo(probabilities[a]);
      return comparison == 0 ? b.compareTo(a) : comparison;
    });
  final winner = ranked.first;
  return {
    'predicted_action': actionClasses[winner],
    'class_index': winner,
    'confidence': probabilities[winner],
    'probabilities': {
      for (var i = 0; i < actionClasses.length; i++)
        actionClasses[i]: probabilities[i],
    },
    'top3': [
      for (final index in ranked.take(3))
        {'action': actionClasses[index], 'probability': probabilities[index]},
    ],
  };
}

Map<String, dynamic> _prediction(
    {int action = 0, double confidence = .95, List<int>? individualActions}) {
  final individual = [
    for (var model = 0; model < modelSeeds.length; model++)
      {
        'seed': modelSeeds[model],
        'available': true,
        ..._decision(List.generate(
            actionClasses.length,
            (index) => index == (individualActions?[model] ?? action)
                ? confidence
                : (1 - confidence) / 7)),
      },
  ];
  final probabilities = [
    for (final action in actionClasses)
      individual.fold<double>(
              0,
              (sum, model) =>
                  sum +
                  ((model['probabilities'] as Map)[action] as num).toDouble()) /
          3,
  ];
  return {
    ..._decision(probabilities),
    'schema_version': predictionSchema,
    'model_version': _version,
    'individual_models': individual,
    'pose_detected': true,
    'normalization_valid': true,
    'recovery_method': 'standard',
    'mean_visibility': .92,
    'inference_ms': 18.0,
    'classifier_disagreement': individual.any((model) =>
        model['class_index'] != _decision(probabilities)['class_index']),
  };
}

Map<String, dynamic> _noPose() => {
      'schema_version': predictionSchema,
      'model_version': _version,
      'predicted_action': null,
      'class_index': null,
      'confidence': 0.0,
      'probabilities': {},
      'top3': [],
      'individual_models': [
        for (final seed in modelSeeds)
          {
            'seed': seed,
            'available': false,
            'predicted_action': null,
            'class_index': null,
            'confidence': 0.0,
            'probabilities': {},
            'top3': [],
          }
      ],
      'pose_detected': false,
      'normalization_valid': false,
      'recovery_method': 'failed',
      'mean_visibility': null,
      'inference_ms': 20.0,
      'warning': 'No finite pose was detected; classifiers were not run.',
    };

SampledFrame _frame(int index, {int? timestamp}) => SampledFrame(
    index, timestamp ?? index * 250, Uint8List.fromList([index, 42, 9]));

class _FakeInference implements LocalInference {
  _FakeInference({this.resultFactory});
  final Map<String, dynamic> Function(int index)? resultFactory;
  final started = <int>[];
  final firstStarted = Completer<void>();
  Completer<void>? firstGate;
  Future<Uint8List?> Function(int)? deferredPreview;
  bool failNext = false, closed = false;
  int active = 0, maximumActive = 0, initializationCount = 0;

  @override
  Future<Map<String, dynamic>> initialize() async {
    initializationCount++;
    return {
      'model_version': _version,
      'pipeline_version': 'test-native-v1',
      'execution_provider': 'CPU',
      'schema_version': predictionSchema
    };
  }

  @override
  Future<LocalFrameResult> analyze(Uint8List jpeg) async {
    active++;
    maximumActive = math.max(maximumActive, active);
    started.add(jpeg.first);
    if (!firstStarted.isCompleted) firstStarted.complete();
    try {
      if (started.length == 1) await firstGate?.future;
      if (failNext) {
        failNext = false;
        throw StateError('MODEL_FAILURE');
      }
      return LocalFrameResult(resultFactory?.call(jpeg.first) ?? _prediction(),
          preview: deferredPreview == null ? Uint8List.fromList(jpeg) : null,
          previewLoader: deferredPreview == null
              ? null
              : () => deferredPreview!(jpeg.first));
    } finally {
      active--;
    }
  }

  @override
  Future<Map<String, dynamic>> report(
          String prayer,
          List<Map<String, dynamic>> samples,
          Map<String, dynamic> options) async =>
      buildLocalReport(prayer, samples, options);

  @override
  Future<void> close() async => closed = true;
}

class _MemoryRepository implements LocalSessionRepository {
  bool failSave = false;
  int saves = 0, deletes = 0;
  final metadata = <String, Map<String, dynamic>>{};
  final images = <String, Map<String, Uint8List>>{};

  @override
  Future<void> save(
      Map<String, dynamic> value, Map<String, Uint8List> evidence) async {
    saves++;
    if (failSave) throw StateError('DISK_FULL');
    final id = value['id'] as String;
    metadata[id] = _clone(value);
    images[id] = {
      for (final item in evidence.entries)
        item.key: Uint8List.fromList(item.value)
    };
  }

  @override
  Future<List<Map<String, dynamic>>> list() async =>
      metadata.values.map(_clone).toList();
  @override
  Future<Map<String, dynamic>?> load(String id) async =>
      metadata[id] == null ? null : _clone(metadata[id]!);
  @override
  Future<Uint8List> evidence(String sessionId, String evidenceId) async =>
      Uint8List.fromList(images[sessionId]![evidenceId]!);
  @override
  Future<void> delete(String id) async {
    deletes++;
    metadata.remove(id);
    images.remove(id);
  }

  @override
  Future<String> export(String id) async => jsonEncode(metadata[id]);
}

Map<String, dynamic> _projectReport(Map<String, dynamic> report) => {
      'overall_result': report['overall_result'],
      'observed_rakahs': report['observed_rakahs'],
      'rakahs': [
        for (final row in report['rakahs'] as List)
          {
            'result': row['result'],
            'stations': [
              for (final station in row['stations'] as List)
                {
                  'station': station['station'],
                  'status': station['status'],
                  'event_id': station['event_id'],
                }
            ],
          }
      ],
      'unexpected': [
        for (final event in report['unexpected_movements'] as List)
          {
            'event_id': event['event_id'],
            'reason': event['reason'],
          }
      ],
    };

void main() {
  for (final live in [false, true]) {
    test(
        'movement score in ${live ? 'live camera' : 'local video'} is saved, exported and synchronized without changing uncertainty',
        () async {
      Map<String, dynamic>? summary;
      PrayerSyncAdapter.binding = 'paired-child';
      PrayerSyncAdapter.sink = (owner, result) async {
        summary = result;
      };
      addTearDown(() {
        PrayerSyncAdapter.binding = null;
        PrayerSyncAdapter.sink = null;
      });
      final repository = _MemoryRepository();
      final session =
          LocalSession(inference: _FakeInference(), repository: repository);
      if (live) {
        final api = LocalLiveAnalysisService(session: session);
        await api.createLive('fajr', 4, null);
        await api.connect();
        await api.sendFrame(_frame(0));
        await api.finishLive(250);
        await api.disconnect();
      } else {
        await session.create('fajr');
        await session.add(_frame(0));
        await session.complete();
      }
      final report = session.report;
      expect(report.movementsExpected, 16);
      expect(report.movementScore, 100 * report.movementsDetected / 16);
      expect(summary!['movement_score'], report.movementScore);
      expect(summary!['movements_detected'], report.movementsDetected);
      expect(summary!['movements_expected'], 16);
      expect(summary!['uncertain'], true);
      expect(summary!['valid'], false);
      final exported = jsonDecode(await session.export()) as Map;
      expect(exported['report']['movement_score'], report.movementScore);
      session.close();
    });
  }
  test('fixed report settings and raw decisions survive save/export', () async {
    final repository = _MemoryRepository();
    final session =
        LocalSession(inference: _FakeInference(), repository: repository);
    await session.create('demo');
    await session.add(_frame(0));
    await session.complete();
    expect(session.report.raw['assessment_options'],
        LocalAssessmentOptions.recommended.toMap());
    expect(session.report.prediction('frame_0'), _prediction());
    expect(session.report.raw['raw_assessment'], isNotNull);
    final exported = jsonDecode(await session.export()) as Map;
    expect(exported['report']['assessment_options'],
        LocalAssessmentOptions.recommended.toMap());
    session.close();
  });
  test(
      'local class order and exactly three complete model decisions are retained',
      () {
    expect(actionClasses, [
      '1_Qiyam',
      '2_Takbir',
      '3_Qiyam_Recitation',
      '4_Ruku',
      '5_Sujud',
      '6_Jalsa',
      '7_Salam_Right',
      '8_Salam_Left'
    ]);
    final prediction = _prediction(individualActions: [0, 3, 0]);
    expect(validPrediction(prediction, _version), isTrue);
    expect(prediction['class_index'], 0);
    expect(prediction['individual_models'], hasLength(3));
    final models = prediction['individual_models'] as List;
    expect(models.map((model) => model['predicted_action']),
        [actionClasses[0], actionClasses[3], actionClasses[0]]);
    for (final action in actionClasses) {
      final mean = models.fold<double>(
              0,
              (sum, model) =>
                  sum + (model['probabilities'][action] as num).toDouble()) /
          3;
      expect(prediction['probabilities'][action], closeTo(mean, 1e-12));
    }
    expect(validPrediction(_noPose(), _version), isTrue);
  });

  test('stale, incomplete and non-arithmetic prediction objects are rejected',
      () {
    expect(
        validPrediction({..._prediction(), 'schema_version': 'old'}, _version),
        isFalse);
    expect(validPrediction(_prediction(), 'different-model'), isFalse);
    expect(
        validPrediction({..._prediction(), 'individual_models': []}, _version),
        isFalse);
    final wrongSeed = _prediction();
    wrongSeed['individual_models'][0]['seed'] = 'other';
    expect(validPrediction(wrongSeed, _version), isFalse);
    final wrongMean = _prediction();
    wrongMean['probabilities'][actionClasses[0]] = .8;
    expect(validPrediction(wrongMean, _version), isFalse);
    final wrongWinner = _prediction();
    wrongWinner['class_index'] = 3;
    wrongWinner['predicted_action'] = actionClasses[3];
    expect(validPrediction(wrongWinner, _version), isFalse);
    final nonFinite = _prediction();
    nonFinite['individual_models'][0]['probabilities'][actionClasses[0]] =
        double.nan;
    expect(validPrediction(nonFinite, _version), isFalse);
  });

  test('individual decisions must agree with their own probability maxima', () {
    final invalid = _prediction();
    invalid['individual_models'][0]['predicted_action'] = actionClasses[3];
    invalid['individual_models'][0]['class_index'] = 3;
    expect(validPrediction(invalid, _version), isFalse);
    final missingDetails = _prediction();
    missingDetails['individual_models'][0].remove('top3');
    expect(validPrediction(missingDetails, _version), isFalse);
    final invalidConfidence = _prediction();
    invalidConfidence['individual_models'][1]['confidence'] = double.nan;
    expect(validPrediction(invalidConfidence, _version), isFalse);
    final malformedFailure = _noPose();
    malformedFailure['individual_models'][1]['predicted_action'] =
        actionClasses[0];
    expect(validPrediction(malformedFailure, _version), isFalse);
  });

  test('model probability arrays must be normalized and inference time finite',
      () {
    final zero = _prediction(confidence: 0);
    zero['individual_models'] = [
      for (final seed in modelSeeds)
        {'seed': seed, ..._decision(List.filled(8, 0))},
    ];
    zero.addAll(_decision(List.filled(8, 0)));
    expect(validPrediction(zero, _version), isFalse);
    expect(
        validPrediction(
            {..._prediction(), 'inference_ms': double.infinity}, _version),
        isFalse);
    expect(validPrediction({..._prediction(), 'inference_ms': -1}, _version),
        isFalse);
  });

  test(
      'gallery capture requires three confident matches, resets, cooldown and dedup',
      () {
    final capture = StableLocalCapture();
    final standing = _prediction();
    expect(capture.update(standing, 0), isFalse);
    expect(capture.update(standing, 250), isFalse);
    expect(capture.update(standing, 500), isTrue);
    expect(capture.update(standing, 3500), isFalse);
    final ruku = _prediction(action: 3);
    expect(capture.update(ruku, 3750), isFalse);
    expect(
        capture.update(_prediction(action: 3, confidence: .69), 4000), isFalse);
    expect(capture.update(ruku, 4250), isFalse);
    expect(capture.update(ruku, 4500), isFalse);
    expect(capture.update(ruku, 4750), isTrue);
    expect(capture.update(_noPose(), 5000), isFalse);
    expect(capture.update(ruku, 8000), isFalse);
    expect(capture.update(ruku, 8250), isFalse);
    expect(capture.update(ruku, 8500), isFalse);
  });

  test(
      'deferred evidence renders only representative or stable captured frames',
      () async {
    final rendered = <int>[];
    final inference = _FakeInference()
      ..deferredPreview = (index) async {
        rendered.add(index);
        return Uint8List.fromList([index]);
      };
    final session =
        LocalSession(inference: inference, repository: _MemoryRepository());
    await session.create('demo');
    for (var i = 0; i < 4; i++) {
      await session.add(_frame(i), live: true);
    }
    expect(rendered, [0, 2]);
    expect(session.samples.length, 4);
    expect(session.captures.single['frame_id'], 'frame_2');
    expect(session.images.keys, ['frame_0', 'frame_2']);
    expect(session.samples.every((s) => validPrediction(s['result'], _version)),
        true);
    session.close();
  });

  test('cancel during deferred evidence cannot retain a stale frame', () async {
    final gate = Completer<Uint8List?>(), started = Completer<void>();
    final inference = _FakeInference()
      ..deferredPreview = (_) {
        started.complete();
        return gate.future;
      };
    final session =
        LocalSession(inference: inference, repository: _MemoryRepository());
    await session.create('demo');
    final frame = session.add(_frame(0));
    await started.future;
    final discard = session.discard();
    gate.complete(Uint8List.fromList([0]));
    await Future.wait([frame, discard]);
    expect(session.samples, isEmpty);
    expect(session.images, isEmpty);
    expect(session.latest, isNull);
    session.close();
  });

  test(
      'concurrent frame submissions are serialized without overlapping inference',
      () async {
    final inference = _FakeInference()..firstGate = Completer<void>();
    final session =
        LocalSession(inference: inference, repository: _MemoryRepository());
    await session.create('demo');
    final first = session.add(_frame(0));
    final second = session.add(_frame(1));
    await inference.firstStarted.future;
    expect(inference.started, [0]);
    expect(inference.maximumActive, 1);
    inference.firstGate!.complete();
    await Future.wait([first, second]);
    expect(inference.started, [0, 1]);
    expect(inference.maximumActive, 1);
    expect(session.samples.map((sample) => sample['sequence_index']), [0, 1]);
    expect(inference.initializationCount, 1);
    session.close();
    await Future<void>.delayed(Duration.zero);
    expect(inference.closed, isTrue);
  });

  test(
      'a failed frame does not poison future local inference, invalid order fails',
      () async {
    final inference = _FakeInference()..failNext = true;
    final session =
        LocalSession(inference: inference, repository: _MemoryRepository());
    await session.create('demo');
    await expectLater(session.add(_frame(0)), throwsStateError);
    await session.add(_frame(1));
    await expectLater(session.add(_frame(2, timestamp: 200)), throwsStateError);
    await session.add(_frame(2));
    expect(session.samples.map((sample) => sample['sequence_index']), [1, 2]);
    expect(inference.maximumActive, 1);
    session.close();
  });

  test('discard rejects queued stale frames and clears latest prediction',
      () async {
    final inference = _FakeInference()..firstGate = Completer<void>();
    final session =
        LocalSession(inference: inference, repository: _MemoryRepository());
    await session.create('demo');
    final first = session.add(_frame(0));
    final second = session.add(_frame(1));
    await inference.firstStarted.future;
    final discard = session.discard();
    inference.firstGate!.complete();
    await Future.wait([first, second, discard]);
    expect(inference.started, [0]);
    expect(session.samples, isEmpty);
    expect(session.images, isEmpty);
    expect(session.latest, isNull);
    await session.create('fajr');
    await session.add(_frame(2));
    expect(session.latest, isNotNull);
    await session.discard();
    expect(session.latest, isNull);
    session.close();
  });

  test(
      'report and saved session retain individual disagreement and evidence locally',
      () async {
    final result = _prediction(individualActions: [0, 3, 0]);
    final inference = _FakeInference(resultFactory: (_) => _clone(result));
    final repository = _MemoryRepository();
    final session = LocalSession(inference: inference, repository: repository);
    final api = LocalAnalysisService(session: session);
    final configuration = await api.configuration();
    expect(api.isLocal, isTrue);
    expect(configuration['mock_enabled'], isFalse);
    await api.create('demo',
        const LocalVideo(name: 'private.mp4', durationMs: 1000), 4, null);
    await api.upload(0, [_frame(0), _frame(1)]);
    await api.complete();
    final report = await api.report();
    expect(report.synthetic, isFalse);
    expect(report.overallResult, 'REVIEW_REQUIRED');
    expect(report.raw['analysis_mode'], 'local');
    expect(report.prediction('frame_0'), result);
    expect(report.prediction('frame_0')!['individual_models'][1]['class_index'],
        3);
    expect(report.prediction('frame_0')!['class_index'], 0);
    expect(report.storageWarning, isNull);
    final id = api.jobId!;
    final saved = (await repository.load(id))!;
    expect(saved['predictions']['frame_0']['individual_models'], hasLength(3));
    expect(await api.evidence('frame_0'), _frame(0).jpeg);
    final exported = jsonDecode(await api.export()) as Map;
    expect(exported['id'], id);
    expect(exported.containsKey('source_video'), isFalse);
    await api.delete(); // Leaving report clears the working session only.
    expect(session.samples, isEmpty);
    expect(await repository.list(), hasLength(1));
    expect(await repository.evidence(id, 'frame_0'), _frame(0).jpeg);
    expect(repository.deletes, 0);
    api.close();
  });

  test(
      'storage failure leaves a visible report and warning without losing decisions',
      () async {
    final repository = _MemoryRepository()..failSave = true;
    final session =
        LocalSession(inference: _FakeInference(), repository: repository);
    await session.create('demo');
    await session.add(_frame(0));
    await session.complete();
    expect(session.report.storageWarning, contains('DISK_FULL'));
    expect(session.report.prediction('frame_0')!['individual_models'],
        hasLength(3));
    expect(await session.evidence('frame_0'), _frame(0).jpeg);
    expect(await repository.list(), isEmpty);
    session.close();
  });

  test(
      'live service records only the third stable decision and preserves it in report',
      () async {
    final session = LocalSession(
        inference: _FakeInference(), repository: _MemoryRepository());
    final api = LocalLiveAnalysisService(session: session);
    await api.createLive('demo', 4, null);
    await api.connect();
    expect(api.connected, isTrue);
    await api.sendFrame(_frame(0));
    await api.sendFrame(_frame(1));
    expect(api.captures, isEmpty);
    await api.sendFrame(_frame(2));
    expect(api.captures, hasLength(1));
    expect(api.captures.single['frame_id'], 'frame_2');
    expect(api.captures.single['result']['individual_models'], hasLength(3));
    await api.sendFrame(_frame(3));
    expect(api.captures, hasLength(1));
    final status = await api.finishLive(1000);
    expect(status['status'], 'COMPLETED');
    expect((await api.report()).capturedActions, hasLength(1));
    await api.disconnect();
    expect(api.connected, isFalse);
    api.close();
  });

  test(
      'native raw sequence report matches all 96 Python golden cases for six prayers',
      () {
    final fixtures = jsonDecode(
        File('browser/test/fixtures/sequence.json').readAsStringSync()) as List;
    expect(fixtures, hasLength(96));
    expect(fixtures.map((fixture) => fixture['prayer']).toSet(),
        prayerCounts.keys.toSet());
    for (var index = 0; index < fixtures.length; index++) {
      final fixture = fixtures[index] as Map;
      final events = (fixture['events'] as List)
          .map((event) => Map<String, dynamic>.from(event as Map))
          .toList();
      final report = localSequence(fixture['prayer'] as String, events);
      expect(_projectReport(report), fixture['expected'],
          reason: 'Python fixture $index (${fixture['prayer']})');
    }
  });

  test(
      'temporal uncertainty and long gaps remain reviewable, never a validity verdict',
      () {
    final samples = [
      {
        'frame_id': 'a',
        'sequence_index': 0,
        'timestamp_ms': 0,
        'result': _prediction(action: 3, confidence: .6)
      },
      {
        'frame_id': 'b',
        'sequence_index': 1,
        'timestamp_ms': 2000,
        'result': _prediction(action: 3)
      },
    ];
    final events = localTemporal(samples);
    expect(events.where((event) => event['observation_status'] == 'uncertain'),
        hasLength(2));
    expect(events.first['candidate_pose'], 'ruku');
    final report = buildLocalReport('demo', samples,
        {'analysis_id': 'local_test', 'model_version': _version});
    expect(report['overall_result'], 'REVIEW_REQUIRED');
    expect(report['notice'], contains('دون حكم على صحة الصلاة'));
    expect(report.containsKey('prayer_valid'), isFalse);
  });

  testWidgets(
      'phone cards show all three decisions and disagreement below aggregate',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LocalPredictionCards(
                    result: _prediction(individualActions: [0, 3, 0]))))));
    await tester.pumpAndSettle();
    for (final seed in modelSeeds) {
      expect(find.text('Model seed $seed'), findsOneWidget);
    }
    expect(find.text('4_Ruku'), findsOneWidget);
    expect(find.text('يختلف عن القرار المجمع — عدم يقين'), findsOneWidget);
    expect(find.text('يتفق مع القرار المجمع'), findsNWidgets(2));
    expect(
        find.text(
            'تختلف قرارات المصنفات؛ راجع النتائج الثلاثة. الثقة لا تقيس صحة الصلاة.'),
        findsOneWidget);
    final aggregate = tester.getTopLeft(find.text('القرار المجمع: القيام'));
    final firstModel = tester.getTopLeft(find.text('Model seed 2026'));
    expect(firstModel.dy, greaterThan(aggregate.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'capture section expands to three decisions and missing results warn',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LocalPredictionCards(
                    result: _prediction(individualActions: [0, 3, 0]),
                    expandable: true)))));
    expect(find.text('Model seed 2026'), findsNothing);
    await tester.tap(find.text('قرارات النماذج الثلاثة'));
    await tester.pumpAndSettle();
    for (final seed in modelSeeds) {
      expect(find.text('Model seed $seed'), findsOneWidget);
    }
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LocalPredictionCards(
                result: {..._prediction(), 'individual_models': const []}))));
    await tester.pumpAndSettle();
    expect(
        find.text('تحذير تشخيصي: النتيجة لا تحتوي على قرارات النماذج الثلاثة.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing local image does not hide any individual classification',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = LocalAnalysisService(
        session: LocalSession(
            inference: _FakeInference(), repository: _MemoryRepository()));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: EvidenceImage(
                    api: service,
                    evidenceId: 'missing',
                    prediction: _prediction(individualActions: [0, 3, 0]))))));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'صورة الدليل غير متاحة في التخزين المحلي. نتائج التصنيف لا تتغير.'),
        findsOneWidget);
    for (final seed in modelSeeds) {
      expect(find.text('Model seed $seed'), findsOneWidget);
    }
    expect(find.text('يختلف عن القرار المجمع — عدم يقين'), findsOneWidget);
    expect(tester.takeException(), isNull);
    service.close();
  });
}
