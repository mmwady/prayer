import '../l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import 'offline_platform.dart';
import 'offline_status.dart';

/// Reflects the static application cache; user media never enters that cache.
class OfflineNotice extends StatefulWidget {
  const OfflineNotice(
      {super.key, this.enabled, this.readStatus, this.applyUpdate});
  final bool? enabled;
  final Future<OfflineStatus> Function()? readStatus;
  final Future<bool> Function()? applyUpdate;

  @override
  State<OfflineNotice> createState() => _OfflineNoticeState();
}

class _OfflineNoticeState extends State<OfflineNotice> {
  OfflineStatus _status = const OfflineStatus(state: 'preparing');
  Timer? _timer;
  bool _reading = false, _applying = false;
  String? _updateError;

  bool get _enabled => widget.enabled ?? kIsWeb;
  @override
  void initState() {
    super.initState();
    if (_enabled) {
      _poll();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    }
  }

  Future<void> _poll() async {
    if (_reading || !mounted) return;
    _reading = true;
    try {
      final status = await (widget.readStatus ?? readOfflineStatus)();
      if (mounted && !_status.sameAs(status)) {
        setState(() => _status = status);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = const OfflineStatus(state: 'unavailable'));
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _update() async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _updateError = null;
    });
    try {
      final applied = await (widget.applyUpdate ?? applyOfflineUpdate)();
      if (!mounted) return;
      if (!applied) {
        setState(() {
          _applying = false;
          _updateError =
              'لم يبدأ التحديث؛ أعد المحاولة بعد اكتمال حفظ الملفات.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _applying = false;
          _updateError = 'تعذر تطبيق التحديث الآن. يمكنك إعادة المحاولة.';
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled || _status.state == 'installed') {
      return const SizedBox.shrink();
    }
    final preparing = _status.state == 'preparing';
    final update = _status.state == 'update_available';
    final ready = _status.ready && _status.state == 'ready';
    final title = _applying
        ? 'جارٍ تطبيق التحديث…'
        : update
            ? 'تحديث التطبيق جاهز'
            : ready
                ? 'جاهز للتدريب دون اتصال'
                : preparing
                    ? 'جارٍ تجهيز التدريب دون إنترنت'
                    : 'لم يكتمل الحفظ للتشغيل دون إنترنت';
    final text = _applying
        ? 'سيُعاد فتح التطبيق بعد اكتمال التحديث.'
        : update
            ? 'يمكنك استخدام النسخة المحفوظة أو تطبيق التحديث. سيُعاد فتح التطبيق عند التحديث.'
            : ready
                ? 'ملفات التدريب والنماذج محفوظة على جهازك. رفيق المسجد يحتاج اتصالًا.'
                : preparing
                    ? 'اترك الصفحة مفتوحة حتى يكتمل حفظ ملفات التطبيق والنماذج.'
                    : 'يمكن التدريب محليًا مع اتصال لتحميل الملفات. جرّب فتح النسخة الآمنة من التطبيق لإكمال الحفظ.';
    return AppCard(
      tone: ready
          ? Tone.ready
          : preparing || _applying
              ? Tone.info
              : Tone.attention,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(
                ready
                    ? Icons.offline_pin_outlined
                    : Icons.download_for_offline_outlined,
                color: ready ? AppColors.accent : AppColors.info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Text(localized(context, title),
                    style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(localized(context, text)),
          if (preparing || _applying) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: _applying ? null : _status.progress),
            if (!_applying && _status.total > 0)
              Text(localized(context, 'حُفظ {0} من {1} ملفًا',
                  [_status.completed, _status.total])),
          ],
          if (update) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _applying ? null : _update,
              icon: const Icon(Icons.system_update_alt),
              label: Text(localized(context, 'تطبيق التحديث')),
            ),
          ],
          if (_updateError != null)
            AppNote(_updateError!, icon: Icons.info_outline),
          const SizedBox(height: AppSpacing.sm),
          Text(localized(context, 'صورك وفيديوهاتك تبقى على جهازك.')),
        ],
      ),
    );
  }
}
