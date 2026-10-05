import 'dart:convert';
import 'dart:io';
import 'package:coaching/local/assessment_options.dart';
import 'package:coaching/local/assessment_widgets.dart';
import 'package:coaching/local/contracts.dart';
import 'package:coaching/local/report_engine.dart';
import 'package:coaching/local/session.dart';
import 'package:coaching/video/analysis_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Fixtures retain the three measured Python model distributions. Small synthetic
// geometry cases duplicate a distribution to isolate the correction rule.
Map<String, dynamic> completePrediction(Map raw) {
  final probabilities =
      Map<String, dynamic>.from(raw['probabilities'] as Map? ?? {});
  final ranked = actionClasses.where(probabilities.containsKey).toList()
    ..sort((a, b) {
      final comparison =
          (probabilities[b] as num).compareTo(probabilities[a] as num);
      return comparison == 0
          ? actionClasses.indexOf(b).compareTo(actionClasses.indexOf(a))
          : comparison;
    });
  final detected = raw['pose_detected'] == true;
  Map<String, dynamic> decisionFor(Map probabilities) {
    final order = actionClasses.where(probabilities.containsKey).toList()
      ..sort((a, b) {
        final comparison =
            (probabilities[b] as num).compareTo(probabilities[a] as num);
        return comparison == 0
            ? actionClasses.indexOf(b).compareTo(actionClasses.indexOf(a))
            : comparison;
      });
    return {
      'predicted_action': detected ? order.first : null,
      'class_index': detected ? actionClasses.indexOf(order.first) : null,
      'confidence': detected ? probabilities[order.first] : 0.0,
      'probabilities': probabilities,
      'top3': [
        for (final a in order.take(3))
          {'action': a, 'probability': probabilities[a]}
      ],
    };
  }

  final decision = {
    'predicted_action': detected ? ranked.first : null,
    'class_index': detected ? actionClasses.indexOf(ranked.first) : null,
    'confidence': detected ? probabilities[ranked.first] : 0.0,
    'probabilities': probabilities,
    'top3': [
      for (final action in ranked.take(3))
        {'action': action, 'probability': probabilities[action]}
    ],
  };
  return {
    ...decision,
    'pose_detected': detected,
    'normalization_valid': detected,
    'schema_version': predictionSchema,
    'model_version': 'measured',
    'inference_ms': 1.0,
    'recovery_method': raw['recovery_method'],
    'individual_models': [
      for (var i = 0; i < modelSeeds.length; i++)
        {
          ...decisionFor(detected &&
                  raw['individual_probabilities'] is List &&
                  (raw['individual_probabilities'] as List).length == 3
              ? {
                  for (var j = 0; j < 8; j++)
                    actionClasses[j]: raw['individual_probabilities'][i][j]
                }
              : probabilities),
          'seed': modelSeeds[i],
          'available': detected,
        }
    ],
  };
}

List<Map<String, dynamic>> samplesFor(Map fixture) => [
      for (final s in fixture['samples'] as List)
        {
          ...Map<String, dynamic>.from(s as Map),
          'result': completePrediction(s['result'] as Map),
        }
    ];

void main() {
  test('actual phone floor glitches do not split rakahs or end at early Salam',
      () {
    final events = (jsonDecode(
            File('test/fixtures/mobile_quality_events.json').readAsStringSync())
        as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    String observations() => jsonEncode([
          for (final e in events)
            {
              for (final key in ['pose', 'start_ms', 'end_ms', 'confidence',
                'candidate_pose', 'candidate_confidence', 'representative_frame_id'])
                key: e[key]
            }
        ]);
    final original = observations();
    final report = localSequence('fajr', events, normalizeSequence: true);
    final rows = report['rakahs'] as List;
    expect(rows.expand((r) => r['stations'] as List)
        .where((s) => s['status'] == 'DETECTED').length, 16);
    final standing = rows[1]['stations'][0] as Map;
    final boundary = events.firstWhere((e) => e['event_id'] == standing['event_id']);
    expect(boundary['start_ms'], 29500);
    expect((rows[1]['stations'] as List).last['timestamp_ms'], 61750);
    expect(observations(), original);
  });
  test(
      'options are independently opt-in; recommended profile excludes experimental sitting',
      () {
    expect(const LocalAssessmentOptions().enabled, false);
    expect(LocalAssessmentOptions.recommended.toMap(), {
      'sequence_normalization': true,
      'ruku_geometry_gate': true,
      'seated_probability_projection': false
    });
  });
  test(
      'Ruku geometry uses prepared-image aspect ratio, visibility, finite and nondegenerate joints',
      () {
    final raw = completePrediction({
      'pose_detected': true,
      'probabilities': {
        for (final name in actionClasses) name: name == '4_Ruku' ? 0.93 : 0.01
      }
    });
    List<Map<String, dynamic>> points() =>
        List.generate(33, (_) => {'x': .5, 'y': .5, 'visibility': 1.0});
    final straight = points();
    straight[23] = {'x': .5, 'y': .2, 'visibility': .9};
    straight[25] = {'x': .5, 'y': .5, 'visibility': .9};
    straight[27] = {'x': .5, 'y': .8, 'visibility': .9};
    Map assess(List p) => assessLocalSample({'result': raw, 'landmarks': p},
        const LocalAssessmentOptions(rukuGeometryGate: true));
    expect(assess(straight)['assessment']['predicted_action'], '4_Ruku');
    for (final p in [
      points(),
      [],
      [
        for (final p in straight) {...p, 'visibility': .49}
      ],
      [
        for (final p in straight) {...p, 'x': double.nan}
      ]
    ]) {
      expect(assess(p)['assessment']['predicted_action'], 'unknown');
      expect(assess(p)['result'], raw);
    }
  });
  final file = File('test/fixtures/local_quality_videos.json');
  final fixtures = jsonDecode(file.readAsStringSync()) as List;
  for (final fixture in fixtures) {
    for (final expected in fixture['reports'] as List) {
      test(
          '${fixture['video']} ${expected['options']} matches Python station assignment',
          () {
        final samples = samplesFor(fixture as Map),
            original = jsonEncode(samples);
        final report = buildLocalReport(fixture['prayer'] as String, samples, {
          ...Map<String, dynamic>.from(expected['options'] as Map),
          'model_version': 'measured'
        });
        expect(jsonEncode(samples), original,
            reason: 'raw predictions/landmarks must remain unchanged');
        for (var r = 0; r < (expected['rakahs'] as List).length; r++) {
          final actualStations = report['rakahs'][r]['stations'] as List,
              expectedStations = expected['rakahs'][r]['stations'] as List;
          for (var j = 0; j < expectedStations.length; j++) {
            for (final key in [
              'station',
              'status',
              'event_id',
              'timestamp_ms'
            ]) {
              expect(actualStations[j][key], expectedStations[j][key],
                  reason: 'rakah $r station $j key $key');
            }
            if (expectedStations[j]['confidence'] != null) {
              expect(
                  actualStations[j]['confidence'],
                  closeTo((expectedStations[j]['confidence'] as num).toDouble(),
                      1e-6));
            }
          }
        }
        final unexpected = [
          for (final e in report['unexpected_movements'] as List)
            {
              for (final k in ['event_id', 'pose', 'start_ms', 'reason'])
                k: e[k]
            }
        ];
        expect(unexpected, expected['unexpected']);
        expect(report['predictions'],
            {for (final s in samples) s['frame_id']: s['result']});
        if (LocalAssessmentOptions.fromMap(
                Map<String, dynamic>.from(expected['options'] as Map))
            .enabled) {
          expect(report['raw_assessment'], isNotNull);
          expect(report['overall_result'], 'REVIEW_REQUIRED');
        }
      });
    }
  }
  testWidgets(
      'optional controls and raw correction disclosure work in Arabic RTL',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final session = LocalSession();
    await tester.pumpWidget(MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                    body: SingleChildScrollView(
                        child: LocalAssessmentControls(
                            session: session,
                            onChanged: () => setState(() {}))))))));
    expect(session.options.enabled, false);
    await tester.tap(find.text('تحسين قراءة الحركات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استخدام إعدادات التحسين المقترحة'));
    await tester.pumpAndSettle();
    expect(session.options.toMap(), LocalAssessmentOptions.recommended.toMap());
    expect(session.options.seatedProbabilityProjection, false);
    final report = AnalysisReport.fromJson(buildLocalReport(
        fixtures.last['prayer'] as String, samplesFor(fixtures.last as Map), {
      'model_version': 'measured',
      ...LocalAssessmentOptions.recommended.toMap()
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LocalAssessmentReview(report: report)))));
    await tester.tap(find.text('أثر التحسينات والنتائج الأصلية'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('زيادة المحطات المؤكدة لا تعني وحدها زيادة الدقة'),
        findsOneWidget);
    expect(find.textContaining('القرار الأصلي:'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
