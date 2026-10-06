import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prayer/local_prayer_reference_repository.dart';
import '../prayer/local_reference_file.dart';
import '../prayer/prayer_content.dart';
import '../prayer/prayer_definition.dart';
import '../prayer/prayer_reference.dart';
import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';

/// On-device authoring of an existing measured reference JSON. The editor
/// preserves imported samples/metadata and validates all six ordered stations.
/// Illustrative teaching assets are deliberately separate from calibration.
class LocalPrayerReferencesScreen extends StatefulWidget {
  const LocalPrayerReferencesScreen({super.key, this.repository});
  final LocalPrayerReferenceRepository? repository;

  @override
  State<LocalPrayerReferencesScreen> createState() =>
      _LocalPrayerReferencesScreenState();
}

class _LocalPrayerReferencesScreenState
    extends State<LocalPrayerReferencesScreen> {
  late final _repository =
      widget.repository ?? LocalPrayerReferenceRepository();
  final _source = TextEditingController();
  PrayerReference? _reference;
  bool _busy = true, _reviewConfirmed = false;
  String? _error, _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reference = await _repository.load();
      if (!mounted) return;
      setState(() {
        _reference = reference;
        _source.text = reference == null ? '' : _repository.export(reference);
        _reviewConfirmed = reference != null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _description(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _description(Object error) => error is FormatException
      ? error.message
      : 'تعذر الوصول إلى التخزين المحلي. يمكنك إعادة المحاولة أو استخدام ملف JSON.';

  Future<void> _importFile() async {
    // The picker is invoked synchronously before any await to retain the gesture.
    final selection = pickLocalReferenceFile();
    try {
      final source = await selection;
      if (!mounted || source == null) return;
      final reference = _repository.parse(source);
      setState(() {
        _source.text = _repository.export(reference);
        _reviewConfirmed = false;
        _error = null;
        _message =
            'تم استيراد الملف إلى المحرر فقط؛ راجعه ثم احفظه لتفعيله محليًا.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _description(error));
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final reference = await _repository.save(_source.text,
          reviewConfirmed: _reviewConfirmed);
      if (mounted) {
        setState(() {
          _reference = reference;
          _message = 'تم حفظ المرجع وتفعيله على هذا الجهاز فقط.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _description(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.clear();
      if (mounted) {
        setState(() {
          _reference = null;
          _source.clear();
          _reviewConfirmed = false;
          _message = 'تم حذف المرجع المحلي. يبقى التعرف بالنماذج متاحًا.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _description(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    try {
      final source = _repository.export(_repository.parse(_source.text));
      final downloaded = await downloadLocalReference(source);
      if (!downloaded) await Clipboard.setData(ClipboardData(text: source));
      if (mounted) {
        setState(() {
          _error = null;
          _message = downloaded
              ? 'تم تصدير المرجع كملف JSON على جهازك.'
              : 'تم نسخ المرجع بصيغة JSON؛ احفظه محليًا في الملف الذي تختاره.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _description(error));
    }
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(localized(context, 'المراجع والإرشادات المحلية'))),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            StatusBanner(
              title: localized(context, 'كل البيانات على جهازك'),
              text: localized(context,
                  'لا يُرفع المرجع أو الصور إلى خادم. التعرف بالنماذج لا يحتاج مرجعًا مُفعَّلًا. مرجع الضبط اختياري ويحتاج أدلة مصوَّرة ومراجعة بشرية.'),
              tone: Tone.info,
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_reference != null)
              StatusBanner(
                title: localized(context, 'المرجع المحلي المفعّل'),
                text: localized(context, '{0} — نسخة {1}، 6 محطات.',
                    [_reference!.name, _reference!.revision]),
                tone: Tone.ready,
              )
            else
              AppNote(
                localized(context,
                    'لا يوجد مرجع مُفعَّل على هذا الجهاز. الرسوم التعليمية أدناه ليست بيانات معايرة.'),
                icon: Icons.info_outline,
              ),
            AppCard(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(localized(context, 'استيراد وتحرير المرجع'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(localized(context,
                    'استورد JSON بالإصدار 2 من مرجع مقاس سابقًا، أو الصق محتواه. يحتفظ المحرر بالنقاط والعينات وبيانات التأليف؛ لا يولّد نقاطًا من الرسوم ولا يستنتج حدود صحة الحركة.')),
                const SizedBox(height: AppSpacing.md),
                if (supportsLocalReferenceFilePicker)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _importFile,
                    icon: const Icon(Icons.file_open_outlined),
                    label:
                        Text(localized(context, 'استيراد ملف JSON من الجهاز')),
                  ),
                TextField(
                  key: const ValueKey('local-reference-json'),
                  controller: _source,
                  enabled: !_busy,
                  minLines: 6,
                  maxLines: 14,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                      labelText: localized(context, 'محتوى المرجع JSON'),
                      helperText: localized(context,
                          'الحد الأقصى 2 ميجابايت. حفظ المرجع محلي فقط.')),
                  onChanged: (_) => setState(() {
                    _reviewConfirmed = false;
                    _message = null;
                  }),
                ),
                CheckboxListTile(
                  value: _reviewConfirmed,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _busy
                      ? null
                      : (value) =>
                          setState(() => _reviewConfirmed = value ?? false),
                  title: Text(localized(context,
                      'أؤكد مراجعة هذا المرجع المصوَّر وملاءمته للضبط التعليمي.')),
                  subtitle: Text(localized(context,
                      'هذا تأكيد المستخدم؛ التطبيق لا يعتمد المرجع دينيًا أو طبيًا.')),
                ),
                Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy || !_reviewConfirmed ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(localized(context, 'حفظ وتفعيل محليًا')),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _busy || _source.text.isEmpty ? null : _export,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(localized(context, 'تصدير JSON')),
                      ),
                      TextButton.icon(
                        onPressed: _busy || _reference == null ? null : _clear,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(localized(context, 'حذف المرجع المحلي')),
                      ),
                    ]),
              ],
            )),
            if (_error != null)
              StatusBanner(
                  text: localized(context, _error!), tone: Tone.danger),
            if (_message != null)
              StatusBanner(
                  text: localized(context, _message!), tone: Tone.info),
            SectionTitle(localized(context, 'الرسوم التعليمية المرفقة'),
                icon: Icons.menu_book_outlined,
                subtitle: localized(context,
                    'للتوضيح فقط؛ لا تُستخدم للحكم على وضعيتك أو لتفعيل مرجع.')),
            _illustration('تكبيرة الإحرام', 'takbir'),
            for (final station in PrayerStation.values)
              _illustration(PrayerContent.labels[station]!, _asset(station)),
            _illustration('التسليم يمينًا', 'salam_right'),
            _illustration('التسليم يسارًا', 'salam_left'),
            AppNote(localized(context, PrayerContent.purpose)),
          ],
        ),
      );

  Widget _illustration(String title, String asset) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(localized(context, title),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Image.asset('assets/prayer_positions/$asset.png',
                height: 240,
                fit: BoxFit.contain,
                semanticLabel: localized(
                    context, 'رسم تعليمي: {0}', [localized(context, title)])),
          ],
        ),
      );

  String _asset(PrayerStation station) => switch (station) {
        PrayerStation.standing => 'standing',
        PrayerStation.ruku => 'ruku',
        PrayerStation.standingAfterRuku => 'standing_after_ruku',
        PrayerStation.sujood1 => 'sujood_first',
        PrayerStation.sittingBetweenSujood => 'sitting',
        PrayerStation.sujood2 => 'sujood_second',
        PrayerStation.intermediateSitting ||
        PrayerStation.finalSitting =>
          'final_sitting',
      };
}
