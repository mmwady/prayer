import 'package:flutter/material.dart';

import '../ui/ui_kit.dart';

/// Scalar coverage is independent of encouragement points and review status.
class MovementProgress extends StatelessWidget {
  const MovementProgress({super.key, required this.progress});

  final Map progress;

  static String summary(Map value, {bool weekly = false}) {
    final prefix = weekly ? 'weekly_' : '';
    final score = value['${prefix}movement_score'];
    if (score is! num) return 'درجة الحركات غير متاحة للنتائج القديمة';
    return '${score.toStringAsFixed(1)}٪ • '
        '${value['${prefix}movements_detected']}/${value['${prefix}movements_expected']} حركة';
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: const Text('اكتمال الحركات المرصودة'),
        subtitle: Text('الأسبوع: ${summary(progress, weekly: true)}'),
        children: [
          ListTile(
            title: const Text('اليوم'),
            subtitle: Text(summary(progress)),
          ),
          for (final day in progress['week'] as List? ?? const [])
            ExpansionTile(
              title: Text('${day['date']}'),
              subtitle: Text(summary(day as Map)),
              children: [
                for (final entry
                    in (day['movement_results'] as Map? ?? const {}).entries)
                  ListTile(
                    title: Text(_prayers[entry.key] ?? '${entry.key}'),
                    subtitle: Text(summary(entry.value as Map)),
                    trailing: PillTag(
                      entry.value['uncertain'] == true
                          ? 'تحتاج مراجعة'
                          : 'تم رصدها',
                      tone: entry.value['uncertain'] == true
                          ? Tone.attention
                          : Tone.info,
                    ),
                  ),
              ],
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
                'نسبة رصد الحركات مستقلة عن النقاط، ولا تعني صحة الصلاة أو قبولها.'),
          ),
        ],
      );
}

const _prayers = {
  'fajr': 'الفجر',
  'dhuhr': 'الظهر',
  'asr': 'العصر',
  'maghrib': 'المغرب',
  'isha': 'العشاء',
};
