import 'package:flutter/material.dart';
import '../config/env.dart';
import 'app_theme.dart';
import 'brand_header.dart';
import 'ui_kit.dart';

class BackendSettingsDrawer extends StatefulWidget {
  const BackendSettingsDrawer({super.key});
  @override
  State<BackendSettingsDrawer> createState() => _BackendSettingsDrawerState();
}

class _BackendSettingsDrawerState extends State<BackendSettingsDrawer> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController(text: Env.backendUrl);
  bool _saving = false;
  String? _message;
  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save({bool reset = false}) async {
    if (!reset && !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      if (reset) {
        await Env.reset();
      } else {
        await Env.save(_url.text);
      }
      if (!mounted) return;
      setState(() {
        _url.text = Env.backendUrl;
        _message = 'تم الحفظ. يُستخدم الرابط عند فتح جلسة جديدة.';
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذر حفظ الرابط. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Drawer(
        backgroundColor: AppColors.canvas,
        child: SafeArea(
            child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const BrandHeader(
                title: 'إعدادات الاتصال',
                subtitle: 'خادم رفيق المسجد فقط؛ التدريب محلي',
                caption: 'اقتدِ'),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
                child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('رابط API',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _url,
                          enabled: !_saving,
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                              hintText: 'https://example.trycloudflare.com'),
                          validator: (value) {
                            try {
                              Env.normalizeUrl(value ?? '');
                              return null;
                            } on FormatException catch (error) {
                              return error.message;
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                            onPressed: _saving ? null : () => _save(),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('حفظ الرابط')),
                        TextButton(
                            onPressed:
                                _saving ? null : () => _save(reset: true),
                            child: const Text('استعادة الرابط الافتراضي')),
                      ],
                    ))),
            const AppNote(
                'أدخل رابط الخادم دون /api. يُحفظ على هذا الجهاز ويُستخدم للجلسات الجديدة.',
                icon: Icons.link),
            if (_message != null) AppNote(_message!),
          ],
        )),
      );
}
