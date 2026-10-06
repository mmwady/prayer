import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';

/// Ordered teaching illustrations, independent of recognition and calibration.
class PrayerIllustrationsScreen extends StatelessWidget {
  const PrayerIllustrationsScreen({super.key});

  static final referenceUrl =
      Uri.parse('https://dorar.net/feqhia/880/الباب-الثالث-صفة-الصلاة');
  static const _movements = [
    ('تكبيرة الإحرام', 'takbir'),
    ('القيام', 'standing'),
    ('الركوع', 'ruku'),
    ('الاعتدال بعد الركوع', 'standing_after_ruku'),
    ('السجود الأول', 'sujood_first'),
    ('الجلوس بين السجدتين', 'sitting'),
    ('السجود الثاني', 'sujood_second'),
    ('الجلوس الأخير', 'final_sitting'),
    ('التسليم يمينًا', 'salam_right'),
    ('التسليم يسارًا', 'salam_left'),
  ];

  Future<void> _openReference(BuildContext context) async {
    try {
      if (await launchUrl(referenceUrl, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Keep the source address available if the browser cannot open it.
    }
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(localized(context, 'تعذر فتح المرجع')),
        content: SelectableText(referenceUrl.toString(),
            textDirection: TextDirection.ltr),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(localized(context, 'إغلاق'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(localized(context, 'التعليم المنظم خطوة بخطوة'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _movements.length + 1,
              itemBuilder: (context, index) {
                if (index == _movements.length) {
                  return AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(localized(context, 'المرجع الشرعي — باب الصلاة'),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: () => _openReference(context),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(
                              localized(context, 'الدرر السنية — صفة الصلاة')),
                        ),
                      ],
                    ),
                  );
                }
                final (title, asset) = _movements[index];
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          localized(context, '{0}. {1}',
                              [index + 1, localized(context, title)]),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Image.asset('assets/prayer_positions/$asset.png',
                          height: 240,
                          fit: BoxFit.contain,
                          semanticLabel: localized(context, title)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
}
