import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/screens/video_analysis_screen.dart';
import 'package:coaching/video/analysis_client.dart';
import 'package:coaching/video/analysis_controller.dart';
import 'package:coaching/video/analysis_report.dart';
import 'package:coaching/video/video_source.dart';

Map<String, dynamic> fixture({bool complete = true}) => {
      'schema_version': '1.0',
      'status': 'COMPLETED',
      'prayer': 'fajr',
      'expected_rakahs': 2,
      'observed_rakahs': complete ? 2 : 1,
      'analysis_mode': 'mock',
      'synthetic': true,
      'notice': mockAnalysisNotice,
      'overall_result': complete ? 'OBSERVED_COMPLETE' : 'REVIEW_REQUIRED',
      'events': [
        {'observation_status': complete ? 'detected' : 'uncertain'}
      ],
      'unexpected_movements': [],
      'rakahs': [
        for (var i = 1; i <= 2; i++)
          {
            'rakah_number': i,
            'result': complete ? 'OBSERVED_COMPLETE' : 'REVIEW_REQUIRED',
            'notes': complete
                ? <String>[]
                : ['لم نتمكن من تأكيد الركوع من الصور المتاحة.'],
            'stations': [
              {
                'station': 'ruku',
                'arabic_label': 'الركوع',
                'status': complete ? 'DETECTED' : 'UNCONFIRMED',
                'confidence': complete ? .96 : null,
                'timestamp_ms': complete ? 2000 : null,
                'evidence_id': complete ? 'e$i' : null
              }
            ],
          }
      ],
    };

const config = {
  'inference_provider': 'mock',
  'mock_enabled': true,
  'frame_sample_fps': 2.0,
  'max_duration_ms': 1200000,
  'max_frames': 2400,
  'batch_frames': 2,
  'max_dimension': 960,
  'max_frame_bytes': 200000,
};

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

class FakeVideo implements VideoSource {
  bool closed = false;
  bool cancelledPick = false;
  Completer<SampledFrame>? held;
  final frames = <int>[];
  @override
  Future<LocalVideo?> pick() async => cancelledPick
      ? null
      : const LocalVideo(name: 'local.mp4', durationMs: 2000);
  @override
  Future<SampledFrame> frame(int index, int timestampMs, int dimension) async {
    frames.add(timestampMs);
    if (held != null) return await held!.future;
    return SampledFrame(index, timestampMs, Uint8List.fromList([1, 2, 3]));
  }

  @override
  Future<void> close() async => closed = true;
}

AnalysisClient fakeApi(List<http.Request> requests,
        {bool fail = false, bool complete = true}) =>
    AnalysisClient(
        baseUrl: 'http://localhost',
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('/config')) return jsonResponse(config);
          if (r.method == 'DELETE') return http.Response('', 204);
          if (r.url.path == '/api/v1/prayer-analyses') {
            return jsonResponse(
                {'job_id': 'job', 'access_token': 'owner'}, 201);
          }
          if (fail && r.url.path.endsWith('/frames')) {
            return jsonResponse({'detail': 'INVALID_JPEG'}, 422);
          }
          if (r.url.path.endsWith('/report')) {
            return jsonResponse(fixture(complete: complete));
          }
          if (r.url.path.contains('/evidence/')) {
            return http.Response.bytes(
                base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
                200);
          }
          return jsonResponse({'status': 'COMPLETED', 'processed_frames': 4});
        }));

class DeferredModelApi extends AnalysisClient
    implements AnalysisPreparationProgress {
  DeferredModelApi() : super(baseUrl: 'http://localhost');
  final ready = Completer<Map<String, dynamic>>();
  int calls = 0;
  @override
  bool get isLocal => true;
  @override
  Map<String, dynamic> get initializationProgress => {
        'phase': 'downloading',
        'asset': 'pose_landmarker_heavy.task',
        'loaded': 1024,
        'total': 2048,
      };
  @override
  Future<Map<String, dynamic>> configuration() {
    calls++;
    return ready.future;
  }
}

void main() {
  test('movement percentage counts detected expected stations only', () {
    final data = fixture();
    data['overall_result'] = 'REVIEW_REQUIRED';
    data['rakahs'][1]['stations'][0]['status'] = 'UNCONFIRMED';
    data['unexpected_movements'] = [
      {'pose': 'ruku'}
    ];
    final report = AnalysisReport.fromJson(data);
    expect(report.movementsExpected, 2);
    expect(report.movementsDetected, 1);
    expect(report.movementScore, 50);
    expect(report.overallResult, 'REVIEW_REQUIRED');
    data['rakahs'] = [];
    expect(AnalysisReport.fromJson(data).movementScore, 0);
  });

  testWidgets('file selection finishes while model progress remains visible',
      (tester) async {
    final api = DeferredModelApi();
    final controller = AnalysisController(source: FakeVideo(), api: api);
    await tester.pumpWidget(MaterialApp(
        home: VideoAnalysisScreen(
            definition: PrayerCatalog.of(PrayerType.fajr),
            controller: controller)));
    // Exercise the controller directly so this test is independent of list scrolling.
    await controller.select();
    await tester.pump();
    expect(controller.video?.name, 'local.mp4');
    expect(controller.preparingModels, isTrue);
    expect(controller.config, isNull);
    expect(find.text('جارٍ فتح الفيديو…'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pump();
    expect(find.textContaining('تحميل موديل الحركة'), findsOneWidget);
    final preparation = controller.prepareModels();
    expect(api.calls, 1);
    api.ready.complete(config);
    await preparation;
    await tester.pump();
    expect(controller.preparingModels, isFalse);
    expect(controller.config, config);
    await tester.pumpWidget(const SizedBox());
  });
  test(
      'strict report version, synthetic labeling and backend results are preserved',
      () {
    final report = AnalysisReport.fromJson(fixture(complete: false));
    expect(report.synthetic, isTrue);
    expect(report.overallResult, 'REVIEW_REQUIRED');
    expect(report.rakahs.last.stations.first.status, 'UNCONFIRMED');
    expect(report.rakahs.last.stations.first.evidenceId, isNull);
    expect(() => AnalysisReport.fromJson({...fixture(), 'schema_version': '9'}),
        throwsFormatException);
    expect(() => AnalysisReport.fromJson({...fixture(), 'synthetic': false}),
        throwsFormatException);
  });

  test(
      'selection, consent, extraction, batches, polling and report transitions',
      () async {
    final requests = <http.Request>[];
    final source = FakeVideo();
    final c = AnalysisController(
        source: source, api: fakeApi(requests), pollInterval: Duration.zero);
    final phases = <AnalysisPhase>[];
    c.addListener(() => phases.add(c.phase));
    await c.select();
    expect(c.video!.name, 'local.mp4');
    await c.start('fajr', consent: false, scenario: 'normal');
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
    await c.start('fajr', consent: true, scenario: 'normal');
    expect(source.frames, [0, 500, 1000, 1500]);
    expect(
        phases,
        containsAll([
          AnalysisPhase.preparing,
          AnalysisPhase.uploading,
          AnalysisPhase.processing,
          AnalysisPhase.completed
        ]));
    expect(c.uploaded, 4);
    expect(c.report!.observedRakahs, 2);
    final uploads =
        requests.where((r) => r.url.path.endsWith('/frames')).toList();
    expect(uploads.length, 2);
    expect(jsonDecode(uploads[1].body)['frames'][0]['timestamp_ms'], 1000);
    expect(uploads.every((r) => r.headers['Authorization'] == 'Bearer owner'),
        isTrue);
    c.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(source.closed, isTrue);
  });

  test('cancelled file picker preserves existing selected video', () async {
    final source = FakeVideo();
    final c = AnalysisController(source: source, api: fakeApi([]));
    await c.select();
    source.cancelledPick = true;
    await c.select();
    expect(c.video!.name, 'local.mp4');
    c.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('backend upload error remains recoverable without completing job',
      () async {
    final requests = <http.Request>[];
    final c = AnalysisController(
        source: FakeVideo(), api: fakeApi(requests, fail: true));
    await c.select();
    await c.start('demo', consent: true, scenario: 'normal');
    expect(c.phase, AnalysisPhase.failed);
    expect(c.error, contains('INVALID_JPEG'));
    expect(requests.where((r) => r.url.path.endsWith('/complete')), isEmpty);
    c.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test(
      'cancel during extraction does not upload pending frames and deletes job',
      () async {
    final requests = <http.Request>[];
    final source = FakeVideo()..held = Completer<SampledFrame>();
    final c = AnalysisController(source: source, api: fakeApi(requests));
    await c.select();
    final operation = c.start('demo', consent: true, scenario: 'normal');
    await Future<void>.delayed(Duration.zero);
    final cancellation = c.cancel();
    source.held!.complete(SampledFrame(0, 0, Uint8List(1)));
    await operation;
    await cancellation;
    expect(c.phase, AnalysisPhase.cancelled);
    expect(requests.where((r) => r.url.path.endsWith('/frames')), isEmpty);
    expect(requests.where((r) => r.method == 'DELETE'), isNotEmpty);
    c.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('selected video, mock label and consent gate are visible',
      (tester) async {
    final c = AnalysisController(source: FakeVideo(), api: fakeApi([]));
    await c.select();
    await tester.pumpWidget(MaterialApp(
        home: VideoAnalysisScreen(
            definition: PrayerCatalog.of(PrayerType.fajr), controller: c)));
    expect(find.text('local.mp4'), findsOneWidget);
    expect(find.text(mockAnalysisNotice), findsOneWidget);
    await tester.scrollUntilVisible(find.text('بدء التحليل بعد الموافقة'), 200);
    final start = tester.widget<FilledButton>(find.ancestor(
        of: find.text('بدء التحليل بعد الموافقة'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton)));
    expect(start.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Arabic per-rakah report renders evidence using owner header',
      (tester) async {
    final requests = <http.Request>[];
    final api = fakeApi(requests)..jobId = 'job';
    api.token = 'owner';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AnalysisResults(
                    report: AnalysisReport.fromJson(fixture()), api: api)))));
    await tester.pumpAndSettle();
    expect(find.text(mockAnalysisNotice), findsOneWidget);
    expect(find.text('الركعة 1'), findsOneWidget);
    expect(find.text('الركعة 2'), findsOneWidget);
    expect(find.text('2 من 2'), findsOneWidget);
    expect(find.text('الركوع — تم رصدها'), findsOneWidget);
    expect(find.textContaining('ثقة'), findsNothing);
    expect(find.textContaining('القرار المجمع'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(requests.first.headers['Authorization'], 'Bearer owner');
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('technical review stays collapsed and preserves private evidence',
      (tester) async {
    final requests = <http.Request>[];
    final api = fakeApi(requests)..jobId = 'job';
    api.token = 'owner';
    final data = fixture(complete: false);
    data['unexpected_movements'] = [
      {
        'pose': 'standing',
        'start_ms': 1000,
        'timestamp_ms': 1250,
        'reason': 'ambiguous',
        'confidence': .82,
        'evidence_id': 'ambiguous',
        'review_rakah_number': 1,
        'review_before_station_index': 0,
      }
    ];
    data['events'] = [
      {
        'observation_status': 'uncertain',
        'candidate_pose': 'ruku',
        'candidate_confidence': .43,
        'candidate_timestamp_ms': 2500,
        'evidence_id': 'uncertain',
        'review_rakah_number': 1,
        'review_before_station_index': 0,
      }
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AnalysisResults(
                    report: AnalysisReport.fromJson(data), api: api)))));
    await tester.pumpAndSettle();
    expect(find.text('حركة محتملة: القيام'), findsNothing);
    expect(requests, isEmpty);
    await tester.scrollUntilVisible(find.text('تفاصيل التحليل والتصدير'), 200);
    await tester.tap(find.text('تفاصيل التحليل والتصدير'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('حركات غير مسندة أو غير متوقعة'), 200);
    await tester.tap(find.text('حركات غير مسندة أو غير متوقعة'));
    await tester.pumpAndSettle();
    expect(find.text('حركة محتملة: القيام'), findsOneWidget);
    expect(find.text('حركة محتملة: الركوع'), findsOneWidget);
    expect(find.textContaining('ثقة الموديل 82٪'), findsOneWidget);
    expect(find.textContaining('ثقة الموديل 43٪'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is Image && widget.image is MemoryImage),
        findsNWidgets(2));
    expect(find.text('الركوع — تحتاج مراجعة'), findsWidgets);
    expect(requests.every((r) => r.headers['Authorization'] == 'Bearer owner'),
        isTrue);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'unconfirmed movements show a reference without invented evidence',
      (tester) async {
    final api = fakeApi([]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AnalysisResults(
                    report: AnalysisReport.fromJson(fixture(complete: false)),
                    api: api)))));
    await tester.pumpAndSettle();
    expect(find.text('الركوع — تحتاج مراجعة'), findsWidgets);
    expect(find.byType(EvidenceImage), findsNothing);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('الصورة التوضيحية'), findsWidgets);
    expect(find.text('توجد حركات تحتاج مراجعة'), findsWidgets);
    expect(find.text('لا توجد لقطة مناسبة للمقارنة'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  test('comparison uses only bounded same-rakah evidence and keeps status', () {
    final json = fixture(complete: false);
    final row = (json['rakahs'] as List).first as Map<String, dynamic>;
    row['stations'] = [
      {
        'station': 'sujood_first',
        'arabic_label': 'السجود الأول',
        'status': 'DETECTED',
        'timestamp_ms': 27000,
        'confidence': 1.0
      },
      {
        'station': 'sitting',
        'arabic_label': 'الجلوس بين السجدتين',
        'status': 'UNCONFIRMED'
      },
      {
        'station': 'sujood_second',
        'arabic_label': 'السجود الثاني',
        'status': 'DETECTED',
        'timestamp_ms': 33000,
        'confidence': .98
      },
    ];
    json['unexpected_movements'] = [
      for (final (id, time, confidence, number) in [
        ('low', 29000, .69, 1),
        ('peak', 30000, .9, 1),
        ('other-rakah', 30000, 1.0, 2),
        ('outside', 34000, 1.0, 1)
      ])
        {
          'evidence_id': id,
          'timestamp_ms': time,
          'confidence': confidence,
          'review_rakah_number': number,
          'review_before_station_index': 2
        },
    ];
    final report = AnalysisReport.fromJson(json);
    final api = fakeApi([]);
    final results = AnalysisResults(report: report, api: api);
    expect(
        results
            .comparisonCandidates(report.rakahs.first, 1)
            .map((e) => e['evidence_id']),
        ['peak', 'low']);
    expect(report.rakahs.first.stations[1].status, 'UNCONFIRMED');
    // Prefer the expected pose over a more confident different movement.
    json['events'] = [
      {
        'pose': 'sitting',
        'timestamp_ms': 31000,
        'representative_frame_id': 'matching',
        'confidence': .5,
      }
    ];
    final matchingReport = AnalysisReport.fromJson(json);
    expect(
        AnalysisResults(report: matchingReport, api: api)
            .comparisonCandidates(matchingReport.rakahs.first, 1)
            .first['evidence_id'],
        'matching');
    // Multiple missing movements receive disjoint temporal slots.
    (row['stations'] as List).insert(2, {
      'station': 'sujood_first',
      'arabic_label': 'السجود',
      'status': 'UNCONFIRMED',
    });
    final gapReport = AnalysisReport.fromJson(json);
    final gapResults = AnalysisResults(report: gapReport, api: api);
    final firstIds = gapResults
        .comparisonCandidates(gapReport.rakahs.first, 1)
        .map((e) => e['evidence_id'])
        .toSet();
    final secondIds = gapResults
        .comparisonCandidates(gapReport.rakahs.first, 2)
        .map((e) => e['evidence_id'])
        .toSet();
    expect(firstIds, isNotEmpty);
    expect(secondIds, isNotEmpty);
    expect(firstIds.intersection(secondIds), isEmpty);

    expect(results.reviewAt(1, 2).map((e) => e['evidence_id']), ['outside']);
    api.close();
  });
}
