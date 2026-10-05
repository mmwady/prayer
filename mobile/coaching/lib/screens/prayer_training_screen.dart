import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../prayer/prayer_definition.dart';
import '../prayer/prayer_content.dart';
import '../prayer/prayer_demo_detector.dart';
import '../prayer/prayer_sequence_engine.dart';
import '../services/pose_detector.dart';
import '../services/pose_detector_provider.dart';
import '../services/prayer_guidance_client.dart';
import '../state/prayer_controller.dart';
import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import '../widgets/ar_overlay.dart';
import '../widgets/prayer_calibration_preview.dart';
import '../prayer/prayer_reference.dart';
import '../prayer/prayer_calibration.dart';
import '../prayer/prayer_floor_check.dart';
import '../prayer/local_prayer_reference_repository.dart';
import 'local_prayer_references_screen.dart';

class PrayerTrainingScreen extends StatefulWidget {
  const PrayerTrainingScreen(
      {super.key,
      required this.definition,
      this.clock,
      this.initialReference,
      this.detectorFactory});
  final PrayerDefinition definition;
  final DateTime Function()? clock;
  final PrayerReference? initialReference;
  final PoseDetector Function()? detectorFactory;
  @override
  State<PrayerTrainingScreen> createState() => _PrayerTrainingScreenState();
}

class _PrayerTrainingScreenState extends State<PrayerTrainingScreen> {
  PrayerController? _controller;
  bool _simulation = false;
  PrayerReference? _reference;
  final _repository = LocalPrayerReferenceRepository();
  PrayerGuidanceSource? _guidance;
  bool _loading = false;
  String? _referenceError;

  @override
  void initState() {
    super.initState();
    _reference = widget.initialReference;
    if (_reference == null) _loadReference();
  }

  Future<void> _loadReference() async {
    setState(() {
      _loading = true;
      _referenceError = null;
      _reference = null;
    });
    try {
      final reference = await _repository.load();
      if (reference != null) PrayerCalibration(reference);
      if (mounted) setState(() => _reference = reference);
    } catch (error) {
      if (mounted) {
        setState(() => _referenceError = error is FormatException
            ? error.message
            : 'تعذر الوصول إلى المرجع المحلي. يمكنك التدريب دون مرجع أو استيراد ملف جديد.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manageReference() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LocalPrayerReferencesScreen(repository: _repository)));
    if (mounted) await _loadReference();
  }

  void _selectSource(bool simulation) {
    final detector = simulation
        ? PrayerDemoDetector(widget.definition)
        : (widget.detectorFactory?.call() ?? getPlatformPoseDetector());
    if (detector is StubPoseDetector) {
      detector.dispose();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'الرصد الحقيقي متاح على الهاتف، أو بفيديو محلي في المتصفح. استخدم المحاكاة للتجربة هنا.')));
      return;
    }
    // Guidance accompanies real observation only. Synthetic simulation runs
    // without it so labelled practice data can never look like coaching.
    final guidance = simulation ? null : const LocalPrayerGuidanceSource();
    setState(() {
      _guidance?.close();
      _guidance = guidance;
      _simulation = simulation;
      _controller = PrayerController(
          definition: widget.definition,
          detector: detector,
          reference: simulation ? null : _reference,
          guidance: guidance,
          clock: widget.clock);
    });
    _controller!
        .start(); // Keep browser file selection within the user gesture.
  }

  @override
  void dispose() {
    _controller?.dispose();
    _guidance?.close();
    super.dispose();
  }

  bool get _isWeb => kIsWeb;
  String get _sourceLabel => _reference != null
      ? (_isWeb
          ? 'اختر فيديو محليًا لضبط التصوير'
          : 'افتح الكاميرا واضبط التصوير')
      : (_isWeb ? 'اختر فيديو للتدريب المحلي' : 'افتح الكاميرا للتدريب المحلي');
  IconData get _sourceIcon =>
      _isWeb ? Icons.video_file_outlined : Icons.camera_alt_outlined;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _setup();
    return ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<PrayerController>(builder: (context, c, _) {
        final s = c.state;
        final active = s.sessionStatus == SessionStatus.active;
        return Scaffold(
          appBar: AppBar(title: Text(widget.definition.arabicName), actions: [
            if (active)
              TextButton(
                  onPressed: c.finish, child: const Text('إنهاء التدريب')),
          ]),
          body: !active
              ? _summary(c, s)
              : c.calibrating
                  ? _calibration(c)
                  : _session(c, s),
        );
      }),
    );
  }

  // ── Setup: pick a source ───────────────────────────────────────────────────
  // Both real observation and the clearly labelled simulation are local.

  Widget _setup() {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.definition.arabicName)),
      // A short settings form rather than a long feed: a single scroll view
      // keeps every control (including the disabled camera button) in the tree
      // so its state is always reachable and testable.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.flag_outlined,
                        color: AppColors.accent, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                        child: Text('قبل أن تبدأ',
                            style: theme.textTheme.titleLarge)),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  Text(PrayerContent.purpose,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(PrayerContent.setup, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            AppCard(
              tone: Tone.info,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.smart_display_outlined,
                        size: 20, color: AppColors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                        child: Text('تجربة سريعة بدون كاميرا',
                            style: theme.textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                      onPressed: () => _selectSource(true),
                      child: const Text('محاكاة للتجربة — دون كاميرا')),
                  const SizedBox(height: AppSpacing.sm),
                  const AppNote(
                      'المحاكاة تعرض بيانات اصطناعية، ولا تقيس حركاتك.'),
                ],
              ),
            ),
            const SectionTitle(
              'الرصد الحقيقي',
              icon: Icons.videocam_outlined,
              subtitle:
                  'فيديو أو كاميرا على جهازك، دون خادم أو خدمة إرشاد خارجية.',
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'مرجع الضبط المحلي اختياري. يمكن التدريب بدونه؛ حينها لا تتم مقارنة وضعيتك بمرجع مُفعَّل.'),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                      onPressed: _loading ? null : _manageReference,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('المراجع والإرشادات المحلية')),
                  if (_loading)
                    const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.md),
                        child: LinearProgressIndicator()),
                ],
              ),
            ),
            if (_referenceError != null)
              StatusBanner(
                  title: 'المرجع المحلي غير متاح',
                  text: _referenceError!,
                  tone: Tone.danger),
            if (_reference != null)
              StatusBanner(
                  title: 'مرجع محلي مفعّل للضبط',
                  text:
                      'المرجع: ${_reference!.name} — نسخة ${_reference!.revision}',
                  tone: Tone.ready),
            AppCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                      onPressed: _loading ? null : () => _selectSource(false),
                      icon: Icon(_sourceIcon),
                      label: Text(_sourceLabel)),
                  const SizedBox(height: AppSpacing.sm),
                  AppNote(_reference == null
                      ? 'لا يوجد مرجع مُفعَّل. سيبدأ التدريب على ترتيب الحركات دون تقييم مطابقتها لمرجع.'
                      : _isWeb
                          ? 'اختر مقطعًا جانبيًا يظهر فيه الجسم كاملًا.'
                          : 'ثبّت الهاتف وأظهر الجسم كاملًا قبل البدء.'),
                  const SizedBox(height: AppSpacing.sm),
                  const AppNote(
                      'هذه شاشة التدريب الهندسي القديمة: تستخدم نقاط الجسم وقواعد محلية، ولا تعرض قرارات النماذج الثلاثة. تحليل الفيديو والكاميرا من بطاقات الصلاة يستخدم محرك النماذج المحلي.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Calibration: frame the body against the reference ─────────────────────

  Widget _calibration(PrayerController c) {
    final theme = Theme.of(context);
    final reference = c.reference!;
    final reading = c.calibration!.reading;
    final ready = c.canBegin;
    final tone = ready
        ? Tone.ready
        : reading.issue == CalibrationIssue.holding
            ? Tone.attention
            : Tone.info;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Row(children: [
          Expanded(
              child: Text('ضبط التصوير قبل الصلاة',
                  style: theme.textTheme.titleLarge)),
          PillTag('نسخة ${reference.revision}'),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text('المرجع: ${reference.name}', style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  _LegendItem(
                      color: Colors.white70, text: 'الرسم الأبيض: المرجع'),
                  _LegendItem(
                      color: AppColors.accent, text: 'الملون: جسمك المرصود'),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * .52)
                    .clamp(220.0, 480.0),
                width: double.infinity,
                child: PrayerCalibrationPreview(
                    detector: c.detector,
                    reference: reference,
                    guideSegment: c.floorCheck.active
                        ? reference.segments[
                            c.floorCheck.phase == FloorCheckPhase.ruku ? 1 : 3]
                        : null,
                    points: c.keypoints,
                    aspectRatio: c.previewAspectRatio,
                    mirrored: c.previewMirrored,
                    ready: ready),
              ),
              const SizedBox(height: AppSpacing.sm),
              const AppNote(
                  'الاتجاه تقريبي: الرسم دليل من المرجع المصوَّر، وليس حكمًا على صحة الوقوف.'),
            ],
          ),
        ),
        StatusBanner(
          text: c.floorCheck.active
              ? '${c.floorCheck.phase == FloorCheckPhase.ruku ? 'انحنِ للركوع' : 'انتقل للسجود'} وثبّت الوضع لتأكيد بقاء الجسم داخل الصورة.${c.floorCheck.visible ? '' : ' أظهر الرأس والقدمين بوضوح.'}'
              : PrayerContent.calibrationLabels[reading.issue]!,
          tone: tone,
          icon: ready ? Icons.check_circle : Icons.center_focus_strong,
        ),
        if (reading.issue == CalibrationIssue.holding && !c.floorCheck.active)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ClipRRect(
              borderRadius: AppRadius.pill,
              child: LinearProgressIndicator(value: reading.progress),
            ),
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                  'تأكد قبل البدء من بقاء الرأس والقدمين داخل الصورة أثناء الركوع والسجود أيضًا. الضبط في القيام وحده لا يضمن ذلك.'),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                  onPressed: ready ? c.startFloorCheck : null,
                  icon: const Icon(Icons.straighten),
                  label: const Text('اختبار مساحة الركوع والسجود (اختياري)')),
              if (c.floorCheck.phase == FloorCheckPhase.completed) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                    '✓ اكتمل فحص مساحة الركوع والسجود. قف مجددًا لتأكيد الضبط قبل البدء.'),
              ],
              if (kIsWeb) ...[
                const SizedBox(height: AppSpacing.sm),
                const AppNote(
                    'للفيديو المحلي: اضبطه عند القيام، ثم أعده إلى البداية عند بدء التدريب.'),
              ],
            ],
          ),
        ),
        if (c.sourceError != null)
          StatusBanner(text: c.sourceError!, tone: Tone.danger),
        if (c.starting)
          const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: LinearProgressIndicator()),
        if (!c.started && !c.starting)
          Center(
            child: TextButton.icon(
                onPressed: c.start,
                icon: const Icon(Icons.refresh),
                label: const Text('حاول مجددًا')),
          ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
            onPressed: ready ? c.beginPrayer : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('ابدأ التدريب')),
      ],
    );
  }

  // ── Live session ───────────────────────────────────────────────────────────

  Widget _session(PrayerController c, PrayerSessionState s) {
    final theme = Theme.of(context);
    final stations = s.definition.rakahs[s.currentRakah - 1].stations;
    final doneInRakah =
        s.completedStations.where((x) => x.rakah == s.currentRakah).length;
    final panelHeight =
        (MediaQuery.sizeOf(context).height * 0.20).clamp(90.0, 220.0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      children: [
        if (_simulation)
          const StatusBanner(
              title: 'وضع المحاكاة',
              text: 'محاكاة — بيانات اصطناعية',
              tone: Tone.attention,
              icon: Icons.smart_display_outlined),
        if (!_simulation)
          StatusBanner(
              title: 'تدريب هندسي محلي',
              text: _reference == null
                  ? 'لم يُحمَّل مرجع للضبط. الرصد تقريبي من قواعد هندسية؛ انخفاض الثقة يوقف التقدم ولا يمثل حكمًا على صحة الصلاة.'
                  : 'يستخدم هذا التدريب قواعد هندسية ومرجع الضبط المحلي، دون إرسال بيانات. ثقة الرصد لا تعني صحة الصلاة.',
              tone: Tone.info),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text('الركعة ${s.currentRakah} من ${s.totalRakahs}',
                        style: theme.textTheme.titleLarge)),
                PillTag(
                    'الحركة ${(doneInRakah + 1).clamp(1, stations.length)} من ${stations.length}',
                    tone: Tone.info),
              ]),
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: AppRadius.pill,
                child: LinearProgressIndicator(
                    value:
                        stations.isEmpty ? 0 : doneInRakah / stations.length),
              ),
            ],
          ),
        ),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.accessibility_new,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                    child: Text('المعاينة', style: theme.textTheme.titleSmall)),
                PillTag(_simulation ? 'اصطناعي' : 'مباشر',
                    tone: _simulation ? Tone.attention : Tone.ready),
              ]),
              const SizedBox(height: AppSpacing.sm),
              _previewPanel(panelHeight,
                  ArOverlay(keypoints: c.keypoints, faultyJoints: const [])),
              const SizedBox(height: AppSpacing.sm),
              _previewPanel(panelHeight, c.detector.buildPreview()),
            ],
          ),
        ),
        Row(children: [
          Expanded(
            child: MetricTile(
                label: 'الوضع المرصود',
                value: PrayerContent.poseLabels[s.observedPose]!,
                icon: Icons.self_improvement,
                tone: Tone.ready),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: MetricTile(
                label: 'ثقة الرصد',
                value: '${(s.confidence.clamp(0, 1) * 100).round()}٪',
                icon: Icons.speed,
                tone: Tone.info),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الحركة التالية', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(PrayerContent.labels[s.expectedStation]!,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.lg),
              StepTracker([
                for (final station in stations)
                  TrackerStep(
                    PrayerContent.labels[station]!,
                    mark: s.completedStations.any((x) =>
                            x.rakah == s.currentRakah && x.station == station)
                        ? StepMark.done
                        : s.expectedStation == station
                            ? StepMark.current
                            : StepMark.pending,
                  ),
              ]),
            ],
          ),
        ),
        StatusBanner(
            text: _feedback(s),
            tone: _feedbackTone(s.feedback),
            icon: _feedbackIcon(s.feedback)),
        _guidanceCard(c),
        if (c.sourceError != null)
          StatusBanner(text: c.sourceError!, tone: Tone.danger),
        if (c.starting)
          const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: LinearProgressIndicator()),
        if (!c.started && !c.starting)
          Center(
            child: TextButton.icon(
                onPressed: c.start,
                icon: const Icon(Icons.refresh),
                label: const Text('حاول مجدداً')),
          ),
      ],
    );
  }

  /// One camera/skeleton panel. Kept as a separate box per source so the
  /// existing split preview architecture is preserved.
  Widget _previewPanel(double height, Widget child) => ClipRRect(
        borderRadius: AppRadius.card,
        child: ColoredBox(
          color: Colors.black,
          child: SizedBox(height: height, width: double.infinity, child: child),
        ),
      );

  String _feedback(PrayerSessionState s) => switch (s.feedback) {
        MovementFeedback.waiting => 'ثبّت الحركة حتى يتم رصدها بوضوح.',
        MovementFeedback.completed =>
          '✓ تم رصد ${PrayerContent.labels[s.currentStation]}، انتقل للحركة التالية.',
        MovementFeedback.lowConfidence =>
          '${PrayerContent.unclear}\n${PrayerContent.adjust}',
        MovementFeedback.skipped => PrayerContent.skipped,
        MovementFeedback.repeated => PrayerContent.repeated,
        MovementFeedback.unexpected => PrayerContent.unexpected,
      };

  Tone _feedbackTone(MovementFeedback feedback) => switch (feedback) {
        MovementFeedback.waiting => Tone.info,
        MovementFeedback.completed => Tone.ready,
        MovementFeedback.lowConfidence => Tone.attention,
        MovementFeedback.skipped => Tone.attention,
        MovementFeedback.repeated => Tone.attention,
        MovementFeedback.unexpected => Tone.attention,
      };

  IconData _feedbackIcon(MovementFeedback feedback) => switch (feedback) {
        MovementFeedback.waiting => Icons.hourglass_empty,
        MovementFeedback.completed => Icons.check_circle_outline,
        MovementFeedback.lowConfidence => Icons.help_outline,
        MovementFeedback.skipped => Icons.skip_next,
        MovementFeedback.repeated => Icons.replay,
        MovementFeedback.unexpected => Icons.error_outline,
      };

  /// Bundled advisory Arabic cue. Renders nothing until there is
  /// either text or an error, so an offline device shows no empty card.
  Widget _guidanceCard(PrayerController c) {
    final text = c.guidanceText;
    if (text == null && c.guidanceError == null && !c.guidancePending) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.lightbulb_outline,
                size: 18, color: AppColors.info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Text('إرشاد محلي', style: theme.textTheme.titleSmall)),
            if (c.guidancePending)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if (text != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(text, style: theme.textTheme.bodyLarge),
          ],
          if (c.guidanceDegraded)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text('تعذر تجهيز الإرشاد المحلي.',
                  style: TextStyle(color: AppColors.warning, fontSize: 12.5)),
            ),
          if (c.guidanceError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(c.guidanceError!,
                  style:
                      const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  // ── Local summary ──────────────────────────────────────────────────────────

  Widget _summary(PrayerController c, PrayerSessionState s) {
    final theme = Theme.of(context);
    final completed = s.sessionStatus == SessionStatus.completed;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      children: [
        AppCard(
          tone: completed ? Tone.ready : Tone.attention,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                  completed
                      ? Icons.verified_outlined
                      : Icons.pause_circle_outline,
                  size: 34,
                  color: completed ? AppColors.accent : AppColors.warning),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(completed ? 'تم إكمال التدريب' : 'تم إيقاف التدريب',
                        style: theme.textTheme.headlineSmall),
                    if (_simulation)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.xs),
                        child: Text('ملخص محاكاة — ليس رصداً لحركاتك'),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text('الصلاة: ${s.definition.arabicName}',
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('الملخص', icon: Icons.insights_outlined),
        AppCard(
          child: Column(children: [
            StatLine(
                text: 'الركعات: ${s.completedRakahs} / ${s.totalRakahs}',
                icon: Icons.check_circle_outline,
                tone: Tone.ready),
            StatLine(
                text:
                    'الحركات المرصودة: ${s.coreMovements} / ${s.definition.coreMovementCount}',
                icon: Icons.accessibility_new,
                tone: Tone.info),
            StatLine(
                text:
                    'الجلوس الإضافي المرصود: ${s.additionalSittings} / ${s.definition.stationCount - s.definition.coreMovementCount}',
                icon: Icons.event_seat_outlined),
            StatLine(
                text: 'إعادات التدريب: ${s.retryCount}', icon: Icons.replay),
            StatLine(
                text: 'حالات انخفاض الثقة: ${s.lowConfidenceEvents}',
                icon: Icons.blur_on),
          ]),
        ),
        if (c.guidanceText != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 18, color: AppColors.info),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text('إرشاد محلي',
                          style: theme.textTheme.titleSmall)),
                ]),
                const SizedBox(height: AppSpacing.sm),
                Text(c.guidanceText!, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        const AppNote(PrayerContent.purpose, icon: Icons.shield_outlined),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('العودة لاختيار الصلاة')),
      ],
    );
  }
}

/// Calibration legend swatch: a short colored dash plus its Arabic label.
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
