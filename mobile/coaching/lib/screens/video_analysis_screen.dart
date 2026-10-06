import '../l10n/app_localizations.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../prayer/prayer_definition.dart';
import '../ui/ui_kit.dart';
import '../ui/app_theme.dart';
import '../ui/brand_header.dart';
import '../video/analysis_client.dart';
import '../video/analysis_controller.dart';
import '../video/analysis_report.dart';
import '../video/video_source_provider.dart';
import 'live_analysis_screen.dart';
import '../local/analysis_service.dart';
import '../local/prediction_cards.dart';
import '../local/assessment_widgets.dart';

const mockAnalysisNotice =
    'محاكاة تحليل — النتائج اصطناعية وليست تحليلًا فعليًا للفيديو';

class VideoAnalysisScreen extends StatefulWidget {
  const VideoAnalysisScreen(
      {super.key, required this.definition, this.controller});
  final PrayerDefinition definition;
  final AnalysisController? controller;
  @override
  State<VideoAnalysisScreen> createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> {
  late final AnalysisController controller;
  bool consent = false, picking = false;
  String scenario = 'normal';
  @override
  void initState() {
    super.initState();
    controller = widget.controller ??
        AnalysisController(
            source: createVideoSource(), api: LocalAnalysisService());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final c = controller;
        return Scaffold(
          appBar: AppBar(
              title: Text(localized(context, 'تحليل فيديو — {0}',
                  [localized(context, widget.definition.arabicName)]))),
          body: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    BrandHeader(
                        title: localized(
                            context,
                            c.report != null
                                ? 'تقرير الحركات'
                                : c.busy
                                    ? 'نتأمل تسلسل الحركات'
                                    : 'كل خطوة تبدأ بلحظة'),
                        subtitle:
                            localized(context, widget.definition.arabicName),
                        caption: localized(
                            context,
                            c.report != null
                                ? 'أدلة من تسجيلك • مراجعة واعية'
                                : 'فيديو مسجل • خصوصية باختيارك')),
                    const SizedBox(height: 20),
                    AppNote(localized(context,
                        'نتابع ترتيب الحركات المرصودة فقط، دون حكم على صحة الصلاة أو قبولها.')),
                    if (c.report == null &&
                        c.config?['inference_provider'] == 'mock')
                      StatusBanner(
                          text: localized(context, mockAnalysisNotice),
                          tone: Tone.attention),
                    if (!c.busy && c.report == null)
                      OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => LiveAnalysisScreen(
                                      definition: widget.definition))),
                          icon: const Icon(Icons.videocam_outlined),
                          label: Text(
                              localized(context, 'تحليل مباشر بالكاميرا'))),
                    if (c.report != null) ...[
                      AnalysisResults(report: c.report!, api: c.api),
                      OutlinedButton.icon(
                          onPressed: () async {
                            if (c.api is LocalResultsService) {
                              await (c.api as LocalResultsService)
                                  .deleteSaved();
                            }
                            await c.cancel();
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label:
                              Text(localized(context, 'حذف التحليل والعودة'))),
                    ] else ...[
                      if (!c.busy) ...[
                        AppCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              SectionTitle(
                                  localized(context, 'فيديو مسجل على جهازك'),
                                  icon: Icons.video_library_outlined),
                              Text(localized(context, 'الصلاة المختارة: {0}', [
                                localized(context, widget.definition.arabicName)
                              ])),
                              if (c.video != null) ...[
                                const SizedBox(height: 12),
                                Text(c.video!.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                Text(localized(context, 'المدة: {0} ثانية', [
                                  (c.video!.durationMs / 1000)
                                      .toStringAsFixed(1)
                                ])),
                              ],
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                  onPressed:
                                      c.busy || picking || c.preparingModels
                                          ? null
                                          : () async {
                                              setState(() {
                                                picking = true;
                                                consent = false;
                                              });
                                              await c.select();
                                              if (mounted) {
                                                setState(() => picking = false);
                                              }
                                            },
                                  icon: const Icon(Icons.folder_open),
                                  label: Text(localized(
                                      context,
                                      picking
                                          ? 'جارٍ فتح الفيديو…'
                                          : 'اختيار فيديو محلي'))),
                            ])),
                        if (c.config?['inference_provider'] == 'mock' &&
                            c.config?['mock_enabled'] == true)
                          AppCard(
                              child: DropdownButtonFormField<String>(
                            initialValue: scenario,
                            isExpanded: true,
                            decoration: InputDecoration(
                                labelText: localized(
                                    context, 'سيناريو تطوير اصطناعي')),
                            items: [
                              DropdownMenuItem(
                                  value: 'normal',
                                  child: Text(localized(
                                      context, 'تسلسل كامل — محاكاة'))),
                              DropdownMenuItem(
                                  value: 'missing_ruku',
                                  child: Text(
                                      localized(context, 'ركوع غير مؤكد'))),
                              DropdownMenuItem(
                                  value: 'missing_sujood',
                                  child: Text(
                                      localized(context, 'سجود غير مؤكد'))),
                              DropdownMenuItem(
                                  value: 'uncertain_pose',
                                  child:
                                      Text(localized(context, 'ثقة منخفضة'))),
                              DropdownMenuItem(
                                  value: 'repeated_movement',
                                  child:
                                      Text(localized(context, 'حركة مكررة'))),
                              DropdownMenuItem(
                                  value: 'wrong_sequence',
                                  child: Text(
                                      localized(context, 'ترتيب غير متوقع'))),
                              DropdownMenuItem(
                                  value: 'incomplete_prayer',
                                  child: Text(
                                      localized(context, 'تسجيل غير مكتمل'))),
                            ],
                            onChanged: c.busy
                                ? null
                                : (value) => setState(() => scenario = value!),
                          )),
                        if (c.config?['inference_provider'] == 'mock' &&
                            c.config?['mock_enabled'] != true)
                          AppNote(localized(context,
                              'المحاكاة غير مفعّلة على الخادم. يلزم تفعيل إعداد التطوير قبل التحليل.')),
                        if (!c.api.isLocal)
                          AppCard(
                              child: CheckboxListTile(
                            value: consent,
                            onChanged: c.busy
                                ? null
                                : (v) => setState(() => consent = v ?? false),
                            title: Text(localized(context,
                                'أوافق على إرسال صور مأخوذة من الفيديو إلى الخادم')),
                            subtitle: Text(localized(context,
                                'يُرفع عدد محدود من إطارات JPEG، وتُحذف تلقائيًا بعد مدة الاحتفاظ أو بطلبك. الفيديو الأصلي يبقى على جهازك.')),
                          )),
                        if (c.preparingModels) ...[
                          const SizedBox(height: 12),
                          _ModelPreparation(progress: c.modelProgress),
                        ],
                        if (c.video != null &&
                            c.config == null &&
                            !c.preparingModels)
                          OutlinedButton.icon(
                              onPressed: () => c.prepareModels(),
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                  localized(context, 'إعادة تجهيز الموديلات'))),
                        FilledButton.icon(
                            onPressed: c.busy ||
                                    (!c.api.isLocal && !consent) ||
                                    c.video == null ||
                                    c.config == null ||
                                    (c.config?['inference_provider'] == 'mock' &&
                                        c.config?['mock_enabled'] != true)
                                ? null
                                : () => c.start(widget.definition.prayerType.name,
                                    consent: consent,
                                    scenario:
                                        c.config?['inference_provider'] == 'mock'
                                            ? scenario
                                            : null),
                            icon: Icon(c.api.isLocal
                                ? Icons.play_arrow
                                : Icons.upload_outlined),
                            label: Text(localized(context,
                                c.api.isLocal ? 'بدء التحليل على جهازك' : 'بدء التحليل بعد الموافقة'))),
                        if (c.api.isLocal)
                          AppNote(
                              localized(context,
                                  'يُقرأ الفيديو وتُحلّل الصور على جهازك فقط. لا تُرسل أي صور أو مدخلات إلى خادم.'),
                              icon: Icons.lock_outline),
                      ],
                      if (c.busy) ...[
                        const SizedBox(height: 20),
                        AppCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(localized(
                                  context,
                                  switch (c.phase) {
                                    AnalysisPhase.preparing =>
                                      'تحضير إطارات الفيديو',
                                    AnalysisPhase.uploading => c.api.isLocal
                                        ? 'تحليل الإطار على جهازك'
                                        : 'رفع دفعة الإطارات',
                                    _ => c.api.isLocal
                                        ? 'إعداد تقرير الحركات محليًا'
                                        : 'الخادم يحلل تسلسل الحركات'
                                  })),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                  value: c.total == 0
                                      ? null
                                      : (c.phase == AnalysisPhase.processing
                                              ? c.processed
                                              : c.uploaded) /
                                          c.total),
                              const SizedBox(height: 8),
                              Text(localized(
                                  context,
                                  c.api.isLocal
                                      ? 'حُللت ${c.uploaded} / ${c.total} صورة محليًا'
                                      : 'تحضير ${c.prepared} • رفع ${c.uploaded} • معالجة ${c.processed} / ${c.total}')),
                              TextButton(
                                  onPressed: c.cancel,
                                  child: Text(localized(
                                      context, 'إلغاء وحذف البيانات'))),
                            ])),
                      ],
                      if (c.error != null)
                        StatusBanner(
                            text: localized(context, c.error!),
                            tone: Tone.danger),
                      if (c.phase == AnalysisPhase.failed)
                        AppNote(localized(context,
                            'يمكنك المحاولة مجددًا بعد معالجة الخطأ. ستُحذف الوظيفة السابقة قبل بدء محاولة جديدة.')),
                      if (c.phase == AnalysisPhase.cancelled)
                        AppNote(localized(context,
                            'أُلغي التحليل. يمكنك اختيار فيديو أو بدء محاولة جديدة.')),
                    ],
                  ]))),
        );
      });
}

class _ModelPreparation extends StatelessWidget {
  const _ModelPreparation({required this.progress});
  final Map<String, dynamic> progress;
  @override
  Widget build(BuildContext context) {
    final downloading = progress['phase'] == 'downloading';
    final loaded = (progress['loaded'] as num?)?.toDouble() ?? 0;
    final total = (progress['total'] as num?)?.toDouble() ?? 0;
    final ratio = total > 0 ? (loaded / total).clamp(0.0, 1.0) : null;
    final asset = progress['asset'] as String? ?? '';
    final model = asset.endsWith('.task')
        ? 'موديل الحركة'
        : asset.endsWith('.onnx')
            ? 'موديل تصنيف الحركات'
            : 'ملفات الموديلات';
    return AppCard(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(downloading
            ? localized(context, 'تحميل {0}{1}', [
                localized(context, model),
                ratio == null
                    ? ''
                    : localized(
                        context, ' — {0}٪', [(ratio * 100).toStringAsFixed(0)]),
              ])
            : localized(context, 'جارٍ تجهيز الموديلات على جهازك…')),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: downloading ? ratio : null),
        if (downloading)
          Text(localized(context, 'تم تحميل {0}{1} ميجابايت', [
            (loaded / 1048576).toStringAsFixed(1),
            localized(context,
                total > 0 ? ' من ${(total / 1048576).toStringAsFixed(1)}' : '')
          ])),
        Text(localized(context,
            'التحميل الأول يحتاج إنترنت. تُحفظ الموديلات محليًا عند توفر مساحة؛ الفيديو يبقى على جهازك.')),
      ],
    ));
  }
}

class AnalysisResults extends StatelessWidget {
  const AnalysisResults(
      {super.key,
      required this.report,
      required this.api,
      this.sourceLabel = 'الفيديو'});
  final AnalysisReport report;
  final AnalysisService api;
  final String sourceLabel;
  Map<String, dynamic>? eventPrediction(Map<String, dynamic> item) {
    var frame = item['representative_frame_id'] ?? item['evidence_id'];
    if (frame == null && item['event_id'] != null) {
      for (final event in report.events) {
        if (event['event_id'] == item['event_id']) {
          frame = event['representative_frame_id'] ?? event['evidence_id'];
          break;
        }
      }
    }
    return report.prediction(frame is String ? frame : null);
  }

  Map<String, dynamic>? stationPrediction(RakahReport rakah, int index) {
    final direct = report.prediction(rakah.stations[index].evidenceId);
    if (direct != null) return direct;
    final rows = report.raw['rakahs'];
    if (rows is List) {
      for (final row in rows) {
        if (row is Map && row['rakah_number'] == rakah.number) {
          final stations = row['stations'];
          if (stations is List &&
              index < stations.length &&
              stations[index] is Map) {
            return eventPrediction(Map<String, dynamic>.from(stations[index]));
          }
        }
      }
    }
    return null;
  }

  Widget reviewSection(
          BuildContext context, List<Map<String, dynamic>> items) =>
      ExpansionTile(
        title: Text(localized(context, 'حركات غير مسندة أو غير متوقعة')),
        subtitle: Text(localized(context, '{0} حركة للمراجعة حسب زمن {1}', [
          items.length,
          localized(context, sourceLabel == 'الكاميرا' ? 'الجلسة' : 'الفيديو')
        ])),
        children: [
          for (final item in items)
            suspectedMovement(context, item,
                uncertain: item['observation_status'] == 'uncertain')
        ],
      );
  List<Map<String, dynamic>> get reviewItems => [
        ...report.unexpected,
        ...report.events.where((e) =>
            e['observation_status'] == 'uncertain' &&
            e['candidate_pose'] != null),
      ]..sort((a, b) =>
          ((a['start_ms'] ?? a['candidate_timestamp_ms'] ?? 0) as int)
              .compareTo(
                  (b['start_ms'] ?? b['candidate_timestamp_ms'] ?? 0) as int));
  List<Map<String, dynamic>> reviewAt(int number, int slot) => reviewItems
      .where((e) =>
          e['review_rakah_number'] == number &&
          e['review_before_station_index'] == slot &&
          !report.rakahs.where((r) => r.number == number).any((r) =>
              r.stations.indexed.any((entry) =>
                  comparisonCandidates(r, entry.$1).any((candidate) =>
                      candidate['evidence_id'] == e['evidence_id']))))
      .toList();
  // Presentation association only: never changes backend station status.
  List<Map<String, dynamic>> comparisonCandidates(
      RakahReport rakah, int index) {
    final stations = rakah.stations;
    if (stations[index].status == 'DETECTED') return [];
    var before = index - 1;
    var after = index + 1;
    while (before >= 0 && stations[before].timestampMs == null) {
      before--;
    }
    while (after < stations.length && stations[after].timestampMs == null) {
      after++;
    }
    // Split a bounded gap into temporal slots so consecutive missing movements
    // cannot all borrow the same frame. No association without both anchors.
    if (before < 0 || after == stations.length) return [];
    final lower = stations[before].timestampMs!;
    final upper = stations[after].timestampMs!;
    if (upper <= lower) return [];
    final missingCount = after - before - 1;
    final slot = index - before - 1;
    final slotStart = lower + (upper - lower) * slot / missingCount;
    final slotEnd = lower + (upper - lower) * (slot + 1) / missingCount;
    final targetTime = (slotStart + slotEnd) / 2;
    const poses = {
      'standing_after_ruku': 'standing',
      'sujood_first': 'sujood',
      'sujood_second': 'sujood',
      'final_sitting': 'sitting',
    };
    final expectedPose = poses[stations[index].key] ?? stations[index].key;
    int? timeOf(Map<String, dynamic> item) => (item['candidate_timestamp_ms'] ??
        item['timestamp_ms'] ??
        item['start_ms']) as int?;
    final assigned = report.rakahs
        .expand((r) => r.stations)
        .map((s) => s.evidenceId)
        .whereType<String>()
        .toSet();
    final unique = <String, Map<String, dynamic>>{};
    for (final item in [...reviewItems, ...report.events]) {
      final time = timeOf(item);
      final evidence = item['evidence_id'] ?? item['representative_frame_id'];
      final number = item['review_rakah_number'];
      if (evidence is! String ||
          assigned.contains(evidence) ||
          (number != null && number != rakah.number) ||
          time == null ||
          time <= lower ||
          time >= upper ||
          time < slotStart ||
          time >= slotEnd) {
        continue;
      }
      unique.putIfAbsent(evidence, () => {...item, 'evidence_id': evidence});
    }
    return unique.values.toList()
      ..sort((a, b) {
        final aMatches = (a['candidate_pose'] ?? a['pose']) == expectedPose;
        final bMatches = (b['candidate_pose'] ?? b['pose']) == expectedPose;
        if (aMatches != bMatches) return aMatches ? -1 : 1;
        final proximity = (timeOf(a)! - targetTime)
            .abs()
            .compareTo((timeOf(b)! - targetTime).abs());
        if (proximity != 0) return proximity;
        return ((b['candidate_confidence'] ?? b['confidence'] ?? 0) as num)
            .compareTo(
                (a['candidate_confidence'] ?? a['confidence'] ?? 0) as num);
      });
  }

  Widget stationComparison(BuildContext context, StationReport station,
      List<Map<String, dynamic>> candidates) {
    const keys = {
      'takbir',
      'standing',
      'ruku',
      'standing_after_ruku',
      'sujood_first',
      'sitting',
      'sujood_second',
      'final_sitting',
      'salam_right',
      'salam_left'
    };
    if (!keys.contains(station.key)) return const SizedBox.shrink();
    Widget example() => Column(children: [
          Text(localized(context, 'الصورة التوضيحية')),
          Image.asset('assets/prayer_positions/${station.key}.png',
              height: 200,
              fit: BoxFit.contain,
              semanticLabel: localized(context, 'صورة مرجعية: {0}',
                  [localized(context, station.label)]),
              errorBuilder: (_, __, ___) =>
                  Text(localized(context, 'تعذر عرض الصورة المرجعية'))),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(localized(context,
          'قارن وضعيتك بالمثال. عدم التأكيد لا يعني أن الوضعية خاطئة.')),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Column(children: [
          Text(localized(context, 'لقطتك في نفس الفترة')),
          if (candidates.isEmpty)
            SizedBox(
                height: 200,
                child: Center(
                    child: Text(
                        localized(context, 'لا توجد لقطة مناسبة للمقارنة'),
                        textAlign: TextAlign.center)))
          else
            EvidenceImage(
                api: api,
                evidenceId: candidates.first['evidence_id'] as String,
                showPrediction: false,
                height: 200),
        ])),
        const SizedBox(width: 8),
        Expanded(child: example()),
      ]),
      if (candidates.isNotEmpty)
        Text(localized(
            context, 'أقرب حركة مرصودة في هذه الفترة؛ للمقارنة فقط.')),
    ]);
  }

  Widget suspectedMovement(BuildContext context, Map<String, dynamic> item,
      {required bool uncertain, bool showEvidence = true}) {
    const labels = {
      'standing': 'القيام',
      'ruku': 'الركوع',
      'sujood': 'السجود',
      'sitting': 'الجلوس',
      'takbir': 'التكبير',
      'salam_right': 'السلام يمينًا',
      'salam_left': 'السلام يسارًا',
    };
    final pose = uncertain ? item['candidate_pose'] : item['pose'];
    final confidence =
        (item[uncertain ? 'candidate_confidence' : 'confidence'] as num?)
            ?.toDouble();
    final timestamp =
        item[uncertain ? 'candidate_timestamp_ms' : 'timestamp_ms'] ??
            item['start_ms'];
    final evidence = item['evidence_id'] as String?;
    return AppCard(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(localized(context, 'حركة محتملة: {0}',
            [localized(context, labels[pose] ?? 'غير محددة')])),
        if (timestamp != null)
          Text(localized(context, 'عند {0} ث{1}', [
            (timestamp / 1000).toStringAsFixed(1),
            localized(
                context,
                confidence == null
                    ? ''
                    : ' • ثقة الموديل ${(confidence * 100).toStringAsFixed(0)}٪')
          ])),
        Text(localized(
            context,
            uncertain
                ? 'رصد غير مؤكد؛ الحركة لم تستوفِ شروط الثقة أو الثبات.'
                : item['reason'] == 'ambiguous'
                    ? 'الحركة مرصودة، لكن إسنادها للركعة ملتبس.'
                    : 'ترتيب غير متوقع أو تكرار.')),
        if (evidence != null && showEvidence) ...[
          if (report.synthetic)
            Text(localized(context,
                'إطار مرتبط بمحاكاة اصطناعية؛ النسبة ليست تعرفًا فعليًا.')),
          EvidenceImage(
              api: api,
              evidenceId: evidence,
              prediction: report.prediction(evidence)),
        ] else if (api.isLocal && showEvidence) ...[
          AppNote(localized(context,
              'صورة هذه الحركة غير متاحة محليًا. تبقى قرارات التصنيف للمراجعة.')),
          LocalPredictionCards(result: eventPrediction(item)),
        ],
      ],
    ));
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (report.synthetic)
          StatusBanner(
              text: localized(context, report.notice), tone: Tone.attention),
        if (report.storageWarning != null)
          StatusBanner(
              text: localized(context, report.storageWarning!),
              tone: Tone.attention),
        MetricTile(
            label: localized(context, 'نسبة اكتمال الحركات'),
            value: localized(
                context, '{0}٪', [report.movementScore.toStringAsFixed(1)]),
            icon: Icons.percent,
            tone: Tone.ready),
        AppNote(localized(context, '{0} من {1} حركة متوقعة تم رصدها{2}.', [
          report.movementsDetected,
          report.movementsExpected,
          localized(
              context,
              report.overallResult == 'REVIEW_REQUIRED'
                  ? ' • النتيجة تحتاج مراجعة'
                  : '')
        ])),
        const SizedBox(height: 12),
        MetricTile(
            label: localized(context, 'عدد الركعات المرصودة'),
            value: localized(context, '{0} من {1}',
                [report.observedRakahs, report.expectedRakahs]),
            icon: Icons.format_list_numbered,
            tone: Tone.ready),
        const SizedBox(height: 12),
        for (final rakah in report.rakahs)
          AppCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                initiallyExpanded: rakah.number == 1,
                title: Text(localized(context, 'الركعة {0}', [rakah.number])),
                subtitle: Text(localized(
                    context,
                    rakah.result == 'OBSERVED_COMPLETE' &&
                            rakah.stations.every((s) => s.status == 'DETECTED')
                        ? 'لا توجد ملاحظات على ترتيب الحركات المرصودة'
                        : 'توجد حركات تحتاج مراجعة')),
                children: [
                  for (final (index, station) in rakah.stations.indexed)
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                Icon(
                                    station.status == 'DETECTED'
                                        ? Icons.check_circle_outline
                                        : Icons.help_outline,
                                    color: station.status == 'DETECTED'
                                        ? AppColors.accent
                                        : AppColors.warning),
                                const SizedBox(width: 8),
                                Expanded(
                                    child:
                                        Text(localized(context, '{0} — {1}', [
                                  localized(context, station.label),
                                  localized(
                                      context,
                                      station.status == 'DETECTED'
                                          ? 'تم رصدها'
                                          : 'تحتاج مراجعة')
                                ]))),
                              ]),
                              if (station.status != 'DETECTED')
                                stationComparison(context, station,
                                    comparisonCandidates(rakah, index))
                              else if (station.evidenceId != null)
                                EvidenceImage(
                                    api: api,
                                    evidenceId: station.evidenceId!,
                                    showPrediction: false)
                              else
                                Text(localized(
                                    context, 'صورة الحركة غير متاحة.')),
                            ])),
                ],
              )),
        AppNote(localized(
            context, 'التقييم لرصد الحركات وترتيبها، دون حكم على صحة الصلاة.')),
        ExpansionTile(
            title: Text(localized(context, 'تفاصيل التحليل والتصدير')),
            children: [
              if (api.isLocal)
                AppNote(
                    localized(context,
                        'التقرير وصور الأدلة على هذا الجهاز. يمكنك حذفها أو تصديرها من السجل المحلي.'),
                    icon: Icons.lock_outline),
              LocalAssessmentReview(report: report),
              if (api is LocalResultsService)
                OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final message =
                            await (api as LocalResultsService).export();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(localized(
                                  context,
                                  message.startsWith('{')
                                      ? 'تم تصدير التقرير محليًا'
                                      : message))));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(localized(
                                  context, 'تعذر التصدير: {0}', [e]))));
                        }
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: Text(localized(context, 'تصدير التقرير المحلي'))),
              if (reviewItems.isNotEmpty) reviewSection(context, reviewItems),
              if (report.capturedActions.isNotEmpty)
                ExpansionTile(
                    title: Text(localized(
                        context,
                        'الأفعال الملتقطة تلقائيًا ({0})',
                        [report.capturedActions.length])),
                    children: [
                      for (final item in report.capturedActions)
                        AppCard(
                            child: LocalPredictionCards(
                                result:
                                    Map<String, dynamic>.from(item['result']),
                                expandable: true)),
                    ]),
            ]),
      ]);
}

class EvidenceImage extends StatefulWidget {
  const EvidenceImage(
      {super.key,
      required this.api,
      required this.evidenceId,
      this.prediction,
      this.showPrediction = true,
      this.height = 260});
  final AnalysisService api;
  final String evidenceId;
  final Map<String, dynamic>? prediction;
  final bool showPrediction;
  final double height;
  @override
  State<EvidenceImage> createState() => _EvidenceImageState();
}

class _EvidenceImageState extends State<EvidenceImage> {
  late final Future<Uint8List> bytes = widget.api.evidence(widget.evidenceId);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FutureBuilder<Uint8List>(
              future: bytes,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(localized(
                      context,
                      widget.api.isLocal
                          ? 'صورة الدليل غير متاحة في التخزين المحلي. نتائج التصنيف لا تتغير.'
                          : 'تعذر تحميل الصورة؛ ربما انتهت مدة الاحتفاظ.'));
                }
                if (!snapshot.hasData) {
                  return const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()));
                }
                return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(snapshot.data!,
                        height: widget.height,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        semanticLabel:
                            localized(context, 'إطار الحركة المرتبط بالتقرير'),
                        errorBuilder: (_, __, ___) =>
                            Text(localized(context, 'تعذر عرض الصورة'))));
              }),
          if (widget.api.isLocal && widget.showPrediction)
            LocalPredictionCards(result: widget.prediction),
        ]),
      );
}
