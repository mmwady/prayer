import '../l10n/app_localizations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../live/camera_provider.dart';
import '../live/live_controller.dart';
import '../prayer/prayer_definition.dart';
import '../ui/brand_header.dart';
import '../ui/ui_kit.dart';
import 'video_analysis_screen.dart';
import '../local/analysis_service.dart';
import '../local/prediction_cards.dart';

class LiveAnalysisScreen extends StatefulWidget {
  const LiveAnalysisScreen(
      {super.key, required this.definition, this.controller});
  final PrayerDefinition definition;
  final LiveController? controller;
  @override
  State<LiveAnalysisScreen> createState() => _LiveAnalysisScreenState();
}

class _LiveAnalysisScreenState extends State<LiveAnalysisScreen>
    with WidgetsBindingObserver {
  late final LiveController controller;
  bool consent = false;
  int? countdown;
  Timer? countdownTimer;

  void cancelCountdown() {
    countdownTimer?.cancel();
    countdownTimer = null;
    countdown = null;
  }

  void startCountdown() {
    if (countdown != null) return;
    setState(() => countdown = 5);
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => countdown = countdown! - 1);
      if (countdown == 0) {
        timer.cancel();
        // Keep zero visible briefly before replacing it with session progress.
        countdownTimer = Timer(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          setState(cancelCountdown);
          unawaited(controller.start(widget.definition.prayerType.name,
              consent: consent,
              scenario: controller.config?['inference_provider'] == 'mock'
                  ? 'normal'
                  : null));
        });
      }
    });
  }

  Widget startButton(LiveController c) => FilledButton.icon(
      onPressed: countdown != null ||
              (!c.api.isLocal && !consent) ||
              c.phase == LivePhase.failed ||
              !c.camera.ready ||
              c.opening ||
              (c.config?['inference_provider'] == 'mock' &&
                  c.config?['mock_enabled'] != true)
          ? null
          : startCountdown,
      icon: const Icon(Icons.play_arrow),
      label: Text(localized(context, 'ابدأ التحليل المباشر')));
  @override
  void initState() {
    super.initState();
    controller = widget.controller ??
        (LiveController(
            camera: createLiveCamera(), api: LocalLiveAnalysisService())
          ..mode = LiveMode.adaptive);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (countdown != null) setState(cancelCountdown);
      if (controller.phase == LivePhase.streaming ||
          controller.phase == LivePhase.reconnecting) {
        controller.error =
            'انتقل التطبيق إلى الخلفية؛ توقف الالتقاط. التقرير يغطي الصور التي وصلت فقط.';
        unawaited(controller.finish());
      } else if (!controller.busy && controller.camera.ready) {
        unawaited(controller.camera.close().then((_) {
          if (mounted) setState(() {});
        }));
      }
    }
  }

  @override
  void dispose() {
    cancelCountdown();
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final c = controller;
        final seconds = c.elapsedMs ~/ 1000;
        final time =
            '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
        return PopScope(
          canPop: !c.busy,
          child: Scaffold(
            appBar: AppBar(
                title: Text(localized(context, 'تحليل مباشر — {0}',
                    [localized(context, widget.definition.arabicName)]))),
            body: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                BrandHeader(
                    title: localized(
                        context,
                        c.report == null
                            ? 'الكاميرا معك أثناء الصلاة'
                            : 'تقرير الحركات'),
                    subtitle: localized(context, widget.definition.arabicName),
                    caption:
                        localized(context, 'صور مباشرة • تقرير بعد الإنهاء')),
                if (c.report == null &&
                    c.config?['inference_provider'] == 'mock')
                  StatusBanner(
                      text: localized(context,
                          'محاكاة تحليل — النتائج اصطناعية وليست تحليلًا فعليًا للكاميرا'),
                      tone: Tone.attention),
                if (c.report != null) ...[
                  if (c.dropped > 0)
                    AppNote(localized(
                        context,
                        c.api.isLocal
                            ? 'تجاوز الالتقاط ${c.dropped} صورة حسب سرعة الجهاز. التقرير يغطي الصور المحللة فقط.'
                            : 'لم تُرسل ${c.dropped} صورة. النتائج تغطي الصور المستلمة فقط.')),
                  AnalysisResults(
                      report: c.report!, api: c.api, sourceLabel: 'الكاميرا'),
                  TextButton(
                      onPressed: () async {
                        if (c.api is LocalResultsService) {
                          await (c.api as LocalResultsService).deleteSaved();
                        }
                        await c.cancel();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child:
                          Text(localized(context, 'حذف صور الجلسة والعودة'))),
                ] else ...[
                  AppNote(localized(context,
                      'ثبّت الهاتف بحيث يظهر الجسم كاملًا أثناء الوقوف والركوع والسجود. انتظر ظهور «التحليل المباشر يعمل» قبل بدء الصلاة، وأبقِ التطبيق مفتوحًا. اضغط «إنهاء الصلاة» بعد الانتهاء.')),
                  if (c.camera.ready)
                    AppCard(
                        child: SizedBox(
                            height: 360,
                            child: Stack(fit: StackFit.expand, children: [
                              c.camera.preview(),
                              if (!c.busy)
                                PositionedDirectional(
                                    top: 12,
                                    start: 12,
                                    child: IconButton.filledTonal(
                                        tooltip: localized(
                                            context, 'تبديل الكاميرا'),
                                        onPressed:
                                            c.opening || countdown != null
                                                ? null
                                                : c.switchCamera,
                                        icon: const Icon(Icons
                                            .flip_camera_android_outlined))),
                              if (countdown != null)
                                Center(
                                    child: Semantics(
                                        liveRegion: true,
                                        label: '$countdown',
                                        child: ExcludeSemantics(
                                            child: Stack(children: [
                                          Text(
                                              localized(
                                                  context, '{0}', [countdown]),
                                              style: TextStyle(
                                                  fontSize: 144,
                                                  height: 1.2,
                                                  fontWeight: FontWeight.w700,
                                                  foreground: Paint()
                                                    ..style =
                                                        PaintingStyle.stroke
                                                    ..strokeWidth = 7
                                                    ..color = Colors.black54)),
                                          Text(
                                              localized(
                                                  context, '{0}', [countdown]),
                                              style: TextStyle(
                                                  fontSize: 144,
                                                  height: 1.2,
                                                  fontWeight: FontWeight.w700,
                                                  foreground: Paint()
                                                    ..style =
                                                        PaintingStyle.stroke
                                                    ..strokeWidth = 3
                                                    ..color = Colors.white)),
                                        ])))),
                            ]))),
                  if (!c.busy && c.camera.ready) startButton(c),
                  if (!c.busy && countdown == null) ...[
                    AppCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(localized(context, 'طريقة التحليل')),
                          const SizedBox(height: 12),
                          SegmentedButton<LiveMode>(
                            segments: [
                              ButtonSegment(
                                  value: LiveMode.buffered,
                                  label: Text(
                                      localized(context, 'التحليل الدقيق')),
                                  icon: const Icon(Icons.inventory_2_outlined)),
                              ButtonSegment(
                                  value: LiveMode.adaptive,
                                  label: Text(
                                      localized(context, 'التحليل السريع')),
                                  icon: const Icon(Icons.speed)),
                            ],
                            selected: {c.mode},
                            onSelectionChanged: c.api.jobId != null
                                ? null
                                : (selection) =>
                                    setState(() => c.mode = selection.single),
                          ),
                          const SizedBox(height: 12),
                          Text(localized(
                              context,
                              c.mode == LiveMode.buffered
                                  ? 'يحفظ كل الصور الملتقطة بالمعدل المحدد ويحللها بالترتيب. قد يستغرق التقرير وقتًا إضافيًا بعد الصلاة.'
                                  : 'يقلل معدل التقاط الصور حسب سرعة المعالجة لتقليل الانتظار. قد تفوت تفاصيل الحركات القصيرة.')),
                          Text(localized(
                              context,
                              c.api.isLocal
                                  ? 'الصور والتحليل على جهازك. أبقِ التطبيق مفتوحًا حتى يكتمل التقرير؛ اكتمال الصور لا يضمن اكتشاف كل حركة.'
                                  : 'اكتمال الصور لا يضمن اكتشاف كل حركة. التخزين مؤقت؛ أبقِ التطبيق مفتوحًا حتى يكتمل الإرسال.')),
                          if (c.config != null)
                            Text(localized(
                                context,
                                'حد الجلسة {0} صورة أو {1} دقيقة. في الدقيق معدل الالتقاط {2} صورة/ثانية. يتوقف الالتقاط عند بلوغ الحد أو امتلاء التخزين.',
                                [
                                  c.config!['max_frames'],
                                  (c.config!['max_duration_ms'] as num) ~/
                                      60000,
                                  c.config!['frame_sample_fps']
                                ])),
                        ])),
                    OutlinedButton.icon(
                        onPressed: c.opening ? null : c.open,
                        icon: const Icon(Icons.videocam_outlined),
                        label: Text(localized(
                            context,
                            c.opening
                                ? 'جارٍ فتح الكاميرا…'
                                : 'فتح الكاميرا وضبط المكان'))),
                    if (!c.api.isLocal)
                      AppCard(
                          child: CheckboxListTile(
                              value: consent,
                              onChanged: (value) =>
                                  setState(() => consent = value ?? false),
                              title: Text(localized(context,
                                  'أوافق على إرسال صور الكاميرا إلى الخادم أثناء الصلاة')),
                              subtitle: Text(localized(context,
                                  'لا يُسجل فيديو ولا صوت. تبدأ مشاركة الصور عند الضغط على ابدأ فقط. تحفظ صور معلقة مؤقتًا على الجهاز حتى يؤكد الخادم حفظها. يمكن حذف بيانات الجلسة.')))),
                    if (!c.camera.ready) startButton(c),
                  ],
                  if (c.busy) ...[
                    AppCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(localized(
                              context,
                              switch (c.phase) {
                                LivePhase.starting => 'جارٍ بدء الجلسة…',
                                LivePhase.reconnecting => c.api.isLocal
                                    ? 'جارٍ استكمال المعالجة المحلية…'
                                    : 'انقطع الاتصال — نحاول الاتصال مجددًا',
                                LivePhase.finishing => c.pending > 0
                                    ? (c.api.isLocal
                                        ? 'انتهى التصوير — جارٍ تحليل الصور المحفوظة محليًا…'
                                        : 'انتهى التصوير — جارٍ إرسال الصور المحفوظة…')
                                    : 'انتهى التصوير — جارٍ استكمال التحليل…',
                                _ => 'التحليل المباشر يعمل • $time'
                              })),
                          const SizedBox(height: 12),
                          Text(localized(
                              context,
                              c.api.isLocal
                                  ? 'التُقطت ${c.captured} • حُللت على الجهاز ${c.processed}'
                                  : 'التُقطت ${c.captured} • حُفظت بالخادم ${c.uploaded} • حُللت ${c.processed}')),
                          Text(localized(
                              context,
                              'معلقة على الجهاز {0} • تنتظر التحليل {1}',
                              [c.pending, c.serverPending])),
                          Text(localized(
                              context,
                              c.mode == LiveMode.buffered
                                  ? 'التحليل الدقيق'
                                  : 'التحليل السريع • معدل الالتقاط ${c.effectiveFps.toStringAsFixed(1)} صورة/ثانية')),
                          if (c.dropped > 0)
                            Text(localized(
                                context,
                                c.api.isLocal
                                    ? 'تجاوز الالتقاط ${c.dropped} صورة؛ قد تبقى بعض الحركات غير مؤكدة.'
                                    : 'لم تُرسل ${c.dropped} صورة؛ قد تبقى بعض الحركات غير مؤكدة.')),
                          if (!c.awake)
                            Text(localized(context,
                                'المتصفح لم يسمح بإبقاء الشاشة مستيقظة. حافظ على الشاشة مفتوحة.')),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: [
                                LivePhase.streaming,
                                LivePhase.reconnecting
                              ].contains(c.phase)
                                  ? c.finish
                                  : null,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: Text(localized(
                                  context, 'إنهاء الصلاة وإظهار التقرير'))),
                        ])),
                    if (c.api.isLocal) ...[
                      AppNote(
                          localized(context,
                              'الصور تبقى على جهازك. الالتقاط التلقائي يتطلب ثلاث قرارات متتالية بثقة كافية؛ ثقة التصنيف لا تعني صحة الصلاة.'),
                          icon: Icons.lock_outline),
                      if (c.api.latestPrediction != null)
                        LocalPredictionCards(result: c.api.latestPrediction),
                      for (final capture in c.api.captures.reversed)
                        AppCard(
                            child: ExpansionTile(
                                title: Text(localized(
                                    context,
                                    'حركة محفوظة • {0} ثانية',
                                    [(capture['timestamp_ms'] as num) / 1000])),
                                children: [
                              LocalPredictionCards(
                                  result: Map<String, dynamic>.from(
                                      capture['result'] as Map),
                                  expandable: true)
                            ])),
                    ],
                  ],
                  if (c.api.jobId != null || c.busy)
                    TextButton(
                        onPressed: c.cancel,
                        child: Text(
                            localized(context, 'إلغاء الجلسة وحذف البيانات'))),
                ],
                if (c.error != null)
                  StatusBanner(
                      text: localized(context, c.error!), tone: Tone.attention),
                if (c.phase == LivePhase.failed &&
                    c.canRetry &&
                    c.api.jobId != null &&
                    (c.uploaded > 0 || c.pending > 0))
                  OutlinedButton(
                      onPressed: c.finish,
                      child: Text(
                          localized(context, 'إعادة محاولة إعداد التقرير'))),
                AppNote(localized(context,
                    'التقرير يتابع الحركات المرصودة، ولا يحكم على صحة الصلاة أو قبولها.')),
              ]),
            )),
          ),
        );
      });
}
