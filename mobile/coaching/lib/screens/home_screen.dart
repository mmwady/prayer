import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../state/locale_provider.dart';
import '../browser/recognizer_screen.dart';

import '../prayer/prayer_definition.dart';
import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import '../ui/brand_header.dart';
import 'video_analysis_screen.dart';
import 'local_prayer_references_screen.dart';
import '../mosque/screen.dart';
import 'local_sessions_screen.dart';
import '../local/offline_notice.dart';
import '../accounts/screen.dart';

/// Prayer picker: the app's entry screen.
///
/// One scrollable list — a short "what this app does" hero, the six prayers and
/// a privacy footnote. A help sheet explains the three-step session flow.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localized(context, 'اقتدِ')),
        actions: [
          PopupMenuButton<String>(
            tooltip: localized(context, 'اللغة'),
            icon: const Icon(Icons.language),
            initialValue: context.watch<LocaleProvider>().localeCode,
            onSelected: context.read<LocaleProvider>().setLocale,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ar', child: Text('العربية')),
              PopupMenuItem(value: 'en', child: Text('English')),
            ],
          ),
          IconButton(
            tooltip: localized(context, 'كيف تستخدم التطبيق'),
            onPressed: () => _showHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
                    AppSpacing.lg, AppSpacing.xxl),
                children: [
                  const BrandHeader(
                      title: 'معك خطوة بخطوة',
                      subtitle: 'تأمل حركاتك بالكاميرا أو من تسجيلك',
                      caption: 'تحليل حركات الصلاة'),
                  const SizedBox(height: AppSpacing.sm),
                  const OfflineNotice(),
                  const AccountEntry(),
                  if (kIsWeb)
                    AppCard(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const BrowserRecognizerScreen())),
                      child: ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined,
                            color: AppColors.accent),
                        title: Text(localized(
                            context, 'تحليل الصور والكاميرا على جهازك')),
                        subtitle: Text(localized(context,
                            'ثلاثة نماذج محلية • الصور لا تُرسل إلى خادم')),
                        trailing: Icon(
                            Directionality.of(context) == TextDirection.rtl
                                ? Icons.chevron_left
                                : Icons.chevron_right),
                      ),
                    ),
                  AppCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MosqueCompanionScreen())),
                    child: ListTile(
                      leading:
                          const Icon(Icons.people_outline, color: AppColors.accent),
                      title: Text(
                          localized(context, 'رفيق المسجد — Mosque Companion')),
                      subtitle: Text(localized(context,
                          'رفيق مشي أو توصيلة ودعم بسيط • ديمو تجريبي')),
                      trailing: Icon(
                          Directionality.of(context) == TextDirection.rtl
                              ? Icons.chevron_left
                              : Icons.chevron_right),
                    ),
                  ),
                  const SectionTitle(
                    'اختر الصلاة',
                    icon: Icons.mosque_outlined,
                    subtitle:
                        'اختر صلاة، ثم اختر فيديو أو افتح الكاميرا للتحليل المحلي.',
                  ),
                  LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth > 650 ? 3 : 2;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final prayer in PrayerCatalog.definitions)
                        SizedBox(
                            width: (constraints.maxWidth - 12 * (columns - 1)) /
                                columns,
                            height: 154 +
                                (MediaQuery.textScalerOf(context).scale(14) -
                                        14) *
                                    3,
                            child: _PrayerCard(prayer: prayer)),
                    ]);
                  }),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const LocalSessionsScreen())),
                      child: ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(localized(context, 'تقاريري على الجهاز')),
                          subtitle: Text(localized(context,
                              'مراجعة وتصدير وحذف جلسات التدريب المحلية')),
                          trailing: Icon(
                              Directionality.of(context) == TextDirection.rtl
                                  ? Icons.chevron_left
                                  : Icons.chevron_right))),
                  AppCard(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const LocalPrayerReferencesScreen())),
                      child: ListTile(
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(localized(context, 'المراجع المحلية')),
                          subtitle: Text(localized(context,
                              'إدارة ملفات المعايرة المراجعة على هذا الجهاز')),
                          trailing: Icon(
                              Directionality.of(context) == TextDirection.rtl
                                  ? Icons.chevron_left
                                  : Icons.chevron_right))),
                  const AppNote(
                    'التدريب والصور والتقارير على جهازك. المتابعة الاختيارية تزامن النتائج النهائية فقط؛ ورفيق المسجد يستخدم الخادم. التطبيق لا يقيّم صحة الصلاة ولا قبولها.',
                    icon: Icons.lock_outline,
                  ),
                ],
              ))),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(localized(context, 'كيف تستخدم التطبيق'),
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  localized(context,
                      'اختر صلاة، ثم فيديو محليًا أو التحليل المباشر بالكاميرا. تُحلل الصور على جهازك ويُحفظ التقرير محليًا بعد الإنهاء.'),
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                const StepTracker([
                  TrackerStep(
                    'اختر الصلاة والفيديو أو الكاميرا',
                    mark: StepMark.done,
                  ),
                  TrackerStep('ابدأ التحليل على جهازك'),
                  TrackerStep('راجع الركعات والحركات وصورها في التقرير'),
                ]),
                const SizedBox(height: AppSpacing.lg),
                const AppNote(
                  'ثلاثة مصنفات محلية تتخذ قرارات مستقلة، ويُعرض متوسط احتمالاتها. يظهر اختلافها كعدم يقين. لا تُرفع الصور أو الفيديوهات.',
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppNote(
                  'التطبيق يتابع ترتيب الحركات فقط. لا يحكم على النية ولا القراءة ولا صحة الصلاة.',
                  icon: Icons.shield_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrayerCard extends StatelessWidget {
  const _PrayerCard({required this.prayer});

  final PrayerDefinition prayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      margin: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoAnalysisScreen(definition: prayer))),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_iconFor(prayer.prayerType), color: AppColors.gold, size: 32),
        const SizedBox(height: 12),
        Text(localized(context, prayer.arabicName),
            style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(_subtitle(prayer),
            style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }

  static String _subtitle(PrayerDefinition prayer) {
    if (prayer.prayerType == PrayerType.demo) {
      return 'ركعة واحدة — للتدريب السريع';
    }
    if (prayer.rakahCount == 2) return 'ركعتان';
    return '${prayer.rakahCount} ركعات';
  }

  static IconData _iconFor(PrayerType type) => switch (type) {
        PrayerType.fajr => Icons.wb_twilight,
        PrayerType.dhuhr => Icons.light_mode_outlined,
        PrayerType.asr => Icons.wb_sunny_outlined,
        PrayerType.maghrib => Icons.brightness_4_outlined,
        PrayerType.isha => Icons.nights_stay_outlined,
        PrayerType.demo => Icons.play_circle_outline,
      };
}
