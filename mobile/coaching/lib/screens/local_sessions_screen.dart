import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../local/contracts.dart';
import '../local/provider.dart';
import '../local/analysis_service.dart';
import '../prayer/prayer_definition.dart';
import '../ui/ui_kit.dart';
import '../video/analysis_report.dart';
import '../video/video_source.dart';
import 'video_analysis_screen.dart';

class LocalSessionsScreen extends StatefulWidget {
  const LocalSessionsScreen({super.key, this.repository});
  final LocalSessionRepository? repository;
  @override
  State<LocalSessionsScreen> createState() => _LocalSessionsScreenState();
}

class _LocalSessionsScreenState extends State<LocalSessionsScreen> {
  late final repository = widget.repository ?? createLocalRepository();
  late Future<List<Map<String, dynamic>>> items = repository.list();
  void refresh() => setState(() => items = repository.list());
  String name(Object? p) => PrayerCatalog.definitions
      .firstWhere((d) => d.prayerType.name == p,
          orElse: () => PrayerCatalog.definitions.last)
      .arabicName;
  Future<void> open(String id) async {
    try {
      final data = await repository.load(id);
      if (data == null) {
        throw StateError('أُبطل التقرير بعد تحديث المحرك أو لم يعد متاحًا');
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SavedReportScreen(
              service: StoredAnalysisService(
                  repository,
                  id,
                  AnalysisReport.fromJson(
                      Map<String, dynamic>.from(data['report']))))));
      if (mounted) refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر فتح التقرير: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تقاريري على الجهاز')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  const AppNote(
                      'التقارير وصور الأدلة محفوظة على هذا الجهاز فقط. يمكنك تصديرها أو حذفها. لا يُحفظ فيديو المصدر في السجل.',
                      icon: Icons.lock_outline),
                  const AppNote(
                      'الحد المحلي 10 جلسات أو 128 MB. عند امتلائه يبقى التقرير الحالي ظاهرًا للتصدير، ولا تُحذف جلسات قديمة تلقائيًا. يُبطل سجل المحرك عند تغير إصدار النموذج أو النتيجة.'),
                  FutureBuilder<List<Map<String, dynamic>>>(
                      future: items,
                      builder: (context, s) {
                        if (s.hasError) {
                          return StatusBanner(
                              text: 'تعذر فتح السجل المحلي: ${s.error}',
                              tone: Tone.attention);
                        }
                        if (!s.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (s.data!.isEmpty) {
                          return const AppNote(
                              'لا توجد جلسات محفوظة بعد. ابدأ تدريبًا من شاشة اختيار الصلاة.');
                        }
                        return Column(children: [
                          for (final item in s.data!)
                            AppCard(
                                onTap: () => open(item['id'] as String),
                                child: ListTile(
                                    leading:
                                        const Icon(Icons.description_outlined),
                                    title: Text(name(item['prayer'])),
                                    subtitle: Text(
                                        '${item['created_at']}\n${item['overall_result'] == 'OBSERVED_COMPLETE' ? 'تسلسل الحركات المرصود مكتمل' : 'يحتاج مراجعة'}'),
                                    trailing: const Icon(Icons.chevron_left)))
                        ]);
                      }),
                ]))),
      );
}

class StoredAnalysisService implements LocalResultsService {
  StoredAnalysisService(this.repository, this.jobId, this.savedReport);
  final LocalSessionRepository repository;
  @override
  final String jobId;
  final AnalysisReport savedReport;
  @override
  bool get isLocal => true;
  @override
  Future<Map<String, dynamic>> configuration() async => localConfiguration;
  @override
  Future<AnalysisReport> report() async => savedReport;
  @override
  Future<Uint8List> evidence(String id) => repository.evidence(jobId, id);
  @override
  Future<String> export() => repository.export(jobId);
  @override
  Future<void> deleteSaved() => repository.delete(jobId);
  @override
  Future<void> delete() async {}
  @override
  void close() {}
  Never _readOnly() => throw StateError('هذا تقرير محفوظ');
  @override
  Future<void> create(String p, LocalVideo v, double f, String? s) async =>
      _readOnly();
  @override
  Future<void> upload(int b, List<SampledFrame> f) async => _readOnly();
  @override
  Future<void> complete() async => _readOnly();
  @override
  Future<Map<String, dynamic>> status() async => {'status': 'COMPLETED'};
}

class _SavedReportScreen extends StatelessWidget {
  const _SavedReportScreen({required this.service});
  final StoredAnalysisService service;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('تقرير محلي محفوظ')),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                AnalysisResults(
                    report: service.savedReport,
                    api: service,
                    sourceLabel: 'السجل المحلي'),
                TextButton.icon(
                    onPressed: () async {
                      await service.deleteSaved();
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف التقرير وصور أدلته من الجهاز'))
              ]))));
}
