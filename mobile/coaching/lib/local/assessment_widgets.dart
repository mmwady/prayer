import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'assessment_options.dart';
import '../video/analysis_report.dart';

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
            title: Text(localized(context, 'أثر التحسينات والنتائج الأصلية')),
            subtitle: Text(localized(
                context,
                'قبل التحسين: {0} / {1} محطة مؤكدة • {2} صورة بتصحيح',
                [detected, rawStations.length, corrections.length])),
            children: [
          if (options.sequenceNormalization)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(localized(context,
                    'إسناد المحطات في هذا التقرير مرجّح بتنقية التسلسل. زيادة المحطات المؤكدة لا تعني وحدها زيادة الدقة.'))),
          for (final row in raw['rakahs'] as List)
            ExpansionTile(
                title: Text(localized(context, 'الركعة {0} — الإسناد الخام',
                    [row['rakah_number']])),
                children: [
                  for (final station in row['stations'] as List)
                    ListTile(
                        title: Text(localized(
                            context, station['arabic_label'] as String)),
                        subtitle: Text(localized(
                            context,
                            station['status'] == 'DETECTED'
                                ? 'مرصودة في التقرير الخام'
                                : 'غير مؤكدة في التقرير الخام'))),
                ]),
          for (final change in corrections.take(20))
            ListTile(
                title: Text(localized(
                    context,
                    (change['reasons'] as List)
                        .map((r) => correctionLabel(r as String))
                        .join('؛ '))),
                subtitle: Text(
                    localized(context, '{0} ث • القرار الأصلي: {1} ({2}٪)', [
                  ((change['timestamp_ms'] as num) / 1000).toStringAsFixed(2),
                  localized(
                      context, rawActionLabel(change['raw_action'] as String?)),
                  ((change['raw_confidence'] as num) * 100).toStringAsFixed(1)
                ]))),
          if (corrections.length > 20)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(localized(
                    context, 'كل التصحيحات محفوظة في ملف التقرير المصدّر.'))),
        ]));
  }
}
