import 'package:flutter/material.dart';
import 'assessment_options.dart';
import 'session.dart';
import '../video/analysis_report.dart';

class LocalAssessmentControls extends StatelessWidget {
  const LocalAssessmentControls(
      {super.key, required this.session, required this.onChanged});
  final LocalSession session;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final options = session.options;
    void update({bool? sequence, bool? ruku, bool? seated}) {
      session.options = LocalAssessmentOptions(
          sequenceNormalization: sequence ?? options.sequenceNormalization,
          rukuGeometryGate: ruku ?? options.rukuGeometryGate,
          seatedProbabilityProjection:
              seated ?? options.seatedProbabilityProjection);
      onChanged();
    }

    return Card(
        child: ExpansionTile(
            title: const Text('تحسين قراءة الحركات'),
            subtitle: Text(options.enabled
                ? 'تحسينات اختيارية مفعّلة'
                : 'النتائج الخام — التحسينات متوقفة'),
            children: [
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  'تساعد هذه الخيارات في قراءة التسلسل. تبقى تنبؤات النماذج الأصلية محفوظة، وتظهر التغييرات في التقرير للمراجعة.')),
          TextButton(
              onPressed: () {
                session.options = LocalAssessmentOptions.recommended;
                onChanged();
              },
              child: const Text('استخدام إعدادات التحسين المقترحة')),
          SwitchListTile(
              value: options.sequenceNormalization,
              title: const Text('تنقية تسلسل الحركات'),
              subtitle: const Text(
                  'يجمع الأحداث المتقطعة ويرجّح ترتيب المحطات؛ لا يثبت صحة الصلاة.'),
              onChanged: (v) => update(sequence: v)),
          SwitchListTile(
              value: options.rukuGeometryGate,
              title: const Text('مراجعة الركوع من وضع الساقين'),
              subtitle: const Text(
                  'يترك الركوع غير مؤكد إذا لم تظهر أدلة كافية على استقامة الساق.'),
              onChanged: (v) => update(ruku: v)),
          SwitchListTile(
              value: options.seatedProbabilityProjection,
              title: const Text('ترجيح وضع الجلوس — تجريبي'),
              subtitle: const Text(
                  'يجمع احتمالات الجلوس والتسليم عند ضعف القرار الفردي؛ قد يضيف أحداثًا زائدة.'),
              onChanged: (v) => update(seated: v)),
        ]));
  }
}

class LocalAssessmentReview extends StatelessWidget {
  const LocalAssessmentReview({super.key, required this.report});
  final AnalysisReport report;
  @override
  Widget build(BuildContext context) {
    final raw = report.raw['raw_assessment'];
    if (raw is! Map) return const SizedBox.shrink();
    final options = LocalAssessmentOptions.fromMap(
        Map<String, dynamic>.from(report.raw['assessment_options'] as Map));
    final corrections = report.raw['corrections'] as List? ?? const [];
    final rawStations = (raw['rakahs'] as List)
        .expand((r) => (r as Map)['stations'] as List)
        .toList();
    final detected =
        rawStations.where((s) => (s as Map)['status'] == 'DETECTED').length;
    return Card(
        child: ExpansionTile(
            title: const Text('أثر التحسينات والنتائج الأصلية'),
            subtitle: Text(
                'قبل التحسين: $detected / ${rawStations.length} محطة مؤكدة • ${corrections.length} صورة بتصحيح'),
            children: [
          if (options.sequenceNormalization)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'إسناد المحطات في هذا التقرير مرجّح بتنقية التسلسل. زيادة المحطات المؤكدة لا تعني وحدها زيادة الدقة.')),
          for (final row in raw['rakahs'] as List)
            ExpansionTile(
                title: Text('الركعة ${row['rakah_number']} — الإسناد الخام'),
                children: [
                  for (final station in row['stations'] as List)
                    ListTile(
                        title: Text(station['arabic_label'] as String),
                        subtitle: Text(station['status'] == 'DETECTED'
                            ? 'مرصودة في التقرير الخام'
                            : 'غير مؤكدة في التقرير الخام')),
                ]),
          for (final change in corrections.take(20))
            ListTile(
                title: Text((change['reasons'] as List)
                    .map((r) => correctionLabel(r as String))
                    .join('؛ ')),
                subtitle: Text(
                    '${((change['timestamp_ms'] as num) / 1000).toStringAsFixed(2)} ث • القرار الأصلي: ${rawActionLabel(change['raw_action'] as String?)} (${((change['raw_confidence'] as num) * 100).toStringAsFixed(1)}٪)')),
          if (corrections.length > 20)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('كل التصحيحات محفوظة في ملف التقرير المصدّر.')),
        ]));
  }
}
