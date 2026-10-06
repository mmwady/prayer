import '../l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import 'controller.dart';
import 'movement_progress.dart';
import 'codes.dart';
import 'family_screen.dart';
import 'mosque_groups_screen.dart';

class AccountEntry extends StatelessWidget {
  const AccountEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AccountController?>();
    if (c == null) return const SizedBox.shrink();
    final signedIn = c.guardian != null;
    final dependent = c.child?['profile_kind'] == 'DEPENDENT';
    return AppCard(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AccountScreen())),
      child: ListTile(
        leading:
            const Icon(Icons.account_circle_outlined, color: AppColors.accent),
        title: Text(localized(
            context,
            signedIn
                ? 'مرحبًا ${c.guardian!['name']}'
                : dependent
                    ? 'جهاز ${c.child!['name']}'
                    : 'الحساب — اختياري')),
        subtitle: Text(localized(
            context,
            signedIn
                ? 'تقدمي • أسرتي • مجموعات المسجد'
                : dependent
                    ? 'التدريب المحلي مرتبط بهذا الملف'
                    : 'تسجيل موحّد للجميع دون اختيار دور دائم')),
        trailing: Icon(Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left
            : Icons.chevron_right),
      ),
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  bool signup = false;
  String learningStage = 'GENERAL';
  String accessibilityMode = 'STANDARD';

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AccountController>();
    return Scaffold(
      appBar: AppBar(title: Text(localized(context, 'الحساب'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const AppNote(
                  'التدريب وتحليل الصلاة يعملان محليًا دون حساب. عند تسجيل الدخول لا تُرسل صور أو فيديو أو بيانات حركة؛ تُزامن ملخصات النتيجة فقط.'),
              if (!c.ready || c.busy) const LinearProgressIndicator(),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(localized(context, c.error!),
                      style: const TextStyle(color: AppColors.warning)),
                ),
              if (c.guardian != null)
                _hub(c)
              else if (c.child?['profile_kind'] == 'DEPENDENT')
                _childHome(c)
              else
                _auth(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _auth(AccountController c) => Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(signup ? 'إنشاء حساب' : 'تسجيل الدخول',
                icon: Icons.person_outline),
            if (signup)
              TextFormField(
                controller: name,
                decoration:
                    InputDecoration(labelText: localized(context, 'الاسم')),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? localized(context, 'أدخل الاسم')
                    : null,
              ),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                  labelText: localized(context, 'البريد الإلكتروني')),
              validator: (value) => value != null && value.contains('@')
                  ? null
                  : localized(context, 'أدخل بريدًا صالحًا'),
            ),
            TextFormField(
              controller: password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                  labelText:
                      localized(context, 'كلمة المرور (8 أحرف على الأقل)')),
              validator: (value) => (value?.length ?? 0) >= 8
                  ? null
                  : localized(context, '8 أحرف على الأقل'),
            ),
            if (signup) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: learningStage,
                decoration: InputDecoration(
                    labelText: localized(context, 'مسار التعلّم — اختياري')),
                items: [
                  DropdownMenuItem(
                      value: 'GENERAL',
                      child: Text(localized(context, 'تعلّم عام'))),
                  DropdownMenuItem(
                      value: 'NEW_MUSLIM',
                      child: Text(localized(context, 'مسلم جديد'))),
                ],
                onChanged: (value) =>
                    setState(() => learningStage = value ?? 'GENERAL'),
              ),
              DropdownButtonFormField<String>(
                initialValue: accessibilityMode,
                decoration: InputDecoration(
                    labelText: localized(context, 'طريقة العرض — اختيارية')),
                items: [
                  DropdownMenuItem(
                      value: 'STANDARD',
                      child: Text(localized(context, 'العرض القياسي'))),
                  DropdownMenuItem(
                      value: 'SIMPLE',
                      child: Text(localized(context, 'واجهة مبسطة'))),
                  DropdownMenuItem(
                      value: 'LARGE_TEXT',
                      child: Text(localized(context, 'نص أكبر'))),
                ],
                onChanged: (value) =>
                    setState(() => accessibilityMode = value ?? 'STANDARD'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: c.busy || !c.ready
                  ? null
                  : () {
                      if (!form.currentState!.validate()) return;
                      c.action(() => c.authenticate(
                            email.text,
                            password.text,
                            fullName: signup ? name.text : null,
                            learningStage: learningStage,
                            accessibilityMode: accessibilityMode,
                          ));
                    },
              child: Text(
                  localized(context, signup ? 'إنشاء الحساب' : 'تسجيل الدخول')),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CodeEntryScreen())),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(localized(context, 'لدي رمز دعوة أو ربط جهاز')),
            ),
            TextButton(
              onPressed: () => setState(() => signup = !signup),
              child: Text(localized(
                  context, signup ? 'لدي حساب بالفعل' : 'إنشاء حساب جديد')),
            ),
            if (!signup) ...[
              TextButton(
                onPressed:
                    c.busy ? null : () => c.action(() => c.recover(email.text)),
                child: Text(localized(context, 'نسيت كلمة المرور')),
              ),
              TextButton(
                onPressed: c.busy
                    ? null
                    : () => c.action(
                        () => c.resendVerification(email.text, password.text)),
                child: Text(localized(context, 'إعادة إرسال رابط التفعيل')),
              ),
            ],
            if (c.child?['profile_kind'] == 'DEPENDENT') ...[
              const Divider(height: 32),
              _linkedProfile(c),
            ],
          ],
        ),
      );

  Widget _childHome(AccountController c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('جهاز المتعلم', icon: Icons.child_care_outlined),
          StatusBanner(
            title: 'تم ربط الجهاز بـ ${c.child!['name']}',
            text:
                'يمكن بدء التدريب بالكاميرا الآن. يستطيع الطفل تسجيل الخروج من الجهاز، وتسجيل الدخول مرة أخرى يتم فقط بربط جديد من ولي الأمر.',
            tone: Tone.ready,
          ),
          const SectionTitle('نتيجتي', icon: Icons.stars_outlined),
          _childScore(c),
          const SectionTitle('مراكزي في مجموعات المسجد',
              icon: Icons.leaderboard_outlined),
          _childGroupRankings(c),
          _linkedProfile(c),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.self_improvement),
            label: Text(localized(context, 'العودة إلى التدريب')),
          ),
          OutlinedButton.icon(
            onPressed: c.busy ? null : () => c.action(c.disconnect),
            icon: const Icon(Icons.logout),
            label: Text(localized(context, 'تسجيل خروج الطفل من هذا الجهاز')),
          ),
          const AppNote(
              'بعد الخروج لا يستطيع الطفل الدخول بكلمة مرور؛ يعيد ولي الأمر ربط الجهاز من إدارة الأسرة.'),
        ],
      );

  Widget _childScore(AccountController c) {
    final score = c.childProgress;
    if (score == null) {
      return AppCard(
        child: ListTile(
          leading: const Icon(Icons.hourglass_empty),
          title: Text(localized(context, 'جارٍ تحميل النتيجة')),
          trailing: IconButton(
            tooltip: localized(context, 'تحديث النتيجة'),
            onPressed: c.busy ? null : () => c.action(c.refreshChildProgress),
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
    }
    return AppCard(
      tone: Tone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.emoji_events)),
            title: Text(localized(context, '{0} نقطة هذا الأسبوع',
                [score['weekly_points'] ?? 0])),
            subtitle: Text(localized(
                context,
                '{0} صلاة مكتملة • {1} أيام متتالية',
                [score['weekly_valid_prayers'] ?? 0, score['streak'] ?? 0])),
            trailing: IconButton(
              tooltip: localized(context, 'تحديث النتيجة'),
              onPressed: c.busy ? null : () => c.action(c.refreshChildProgress),
              icon: const Icon(Icons.refresh),
            ),
          ),
          LinearProgressIndicator(
            value: ((score['valid_prayers'] as num? ?? 0) / 5)
                .clamp(0.0, 1.0)
                .toDouble(),
          ),
          const SizedBox(height: 8),
          Text(localized(context, 'اليوم: {0} من 5 صلوات مكتملة',
              [score['valid_prayers'] ?? 0])),
          MovementProgress(progress: score),
        ],
      ),
    );
  }

  Widget _childGroupRankings(AccountController c) {
    final rows = c.childProgress?['group_rankings'] as List? ?? const [];
    if (rows.isEmpty) {
      return const StatusBanner(
        text: 'لست عضوًا في مجموعة مسجد بعد.',
        tone: Tone.neutral,
      );
    }
    return Column(
      children: [
        for (final raw in rows)
          Builder(builder: (context) {
            final row = raw as Map;
            final enabled = row['leaderboard_enabled'] == true;
            return AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: enabled && row['practice_position'] != null
                      ? Text('${row['practice_position']}')
                      : const Icon(Icons.lock_outline),
                ),
                title: Text('${row['mosque_name']} — ${row['group_name']}'),
                subtitle: Text(localized(
                    context,
                    enabled
                        ? 'الاسم: ${row['alias']} • ${row['weekly_points'] ?? 0} نقطة'
                        : 'ولي الأمر عطّل الظهور في لوحة الترتيب.')),
                trailing: enabled && row['practice_position'] != null
                    ? PillTag(
                        '${row['practice_position']} من ${row['participants']}',
                        tone: Tone.ready,
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }

  Widget _hub(AccountController c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(localized(context, 'السلام عليكم، {0}', [c.guardian!['name']]),
              style: Theme.of(context).textTheme.headlineSmall),
          if (c.pendingInvitation != null)
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.mark_email_unread_outlined,
                    color: AppColors.accent),
                title: Text(localized(context, 'دعوة مسجد بانتظار الإكمال')),
                subtitle: Text(localized(
                    context, 'اختر ملفك أو طفلك ثم وافق على المشاركة.')),
                trailing: FilledButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MosqueJoinScreen(
                          initialToken: c.pendingInvitation!))),
                  child: Text(localized(context, 'إكمال')),
                ),
              ),
            ),
          AppCard(
            child: ListTile(
              leading:
                  const Icon(Icons.self_improvement, color: AppColors.accent),
              title: Text(localized(context, 'تقدمي الشخصي')),
              subtitle: Text(localized(
                  context,
                  c.child?['profile_kind'] == 'SELF'
                      ? 'نتائج التدريب بالكاميرا مرتبطة بحسابك'
                      : 'اختر ملفك الشخصي لمزامنة ملخصات التدريب')),
              trailing: Icon(Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          if (c.child != null) _childScore(c),
          AppCard(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FamilyScreen())),
            child: ListTile(
              leading: const Icon(Icons.family_restroom, color: AppColors.accent),
              title: Text(localized(context, 'أسرتي')),
              subtitle: Text(localized(
                  context, 'أفراد الأسرة • الأطفال • الأجهزة • الموافقات')),
              trailing: Icon(Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right),
            ),
          ),
          AppCard(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MosqueGroupsScreen())),
            child: ListTile(
              leading: const Icon(Icons.groups_outlined, color: AppColors.accent),
              title: Text(localized(context, 'مجموعات المسجد')),
              subtitle: Text(localized(
                  context, 'الانضمام بموافقة ولي الأمر • الحضور • التشجيع')),
              trailing: Icon(Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right),
            ),
          ),
          AppCard(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MosqueAccessScreen())),
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined,
                  color: AppColors.accent),
              title: Text(localized(context, 'صلاحيات وإدارة المسجد')),
              subtitle: Text(localized(context,
                  'طلب صلاحية قائد • متابعة التحقق • إدارة الطلبات للمسؤول العام')),
              trailing: Icon(Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const MosqueJoinScreen(target: 'SELF'))),
            icon: const Icon(Icons.person_add_alt),
            label: Text(localized(context, 'مسح QR والانضمام بنفسي')),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const MosqueJoinScreen(target: 'CHILD'))),
            icon: const Icon(Icons.child_care),
            label: Text(localized(context, 'مسح QR وضم طفل بموافقتي')),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CodeEntryScreen())),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(localized(context, 'استخدام رمز دعوة أو حضور أو جهاز')),
          ),
          if (c.child != null) _linkedProfile(c),
          TextButton(
            onPressed: c.busy ? null : () => c.action(c.logout),
            child: Text(localized(context, 'تسجيل الخروج')),
          ),
        ],
      );

  Widget _linkedProfile(AccountController c) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text(
                  localized(context, 'ملف التدريب: {0}', [c.child!['name']])),
              subtitle: Text(localized(
                  context, '{0} نتيجة تنتظر المزامنة', [c.queue.length])),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: c.syncing ? null : c.sync,
                  icon: const Icon(Icons.sync),
                  label: Text(localized(context, 'مزامنة')),
                ),
              ],
            )
          ],
        ),
      );
}

class CodeEntryScreen extends StatefulWidget {
  const CodeEntryScreen({super.key});

  @override
  State<CodeEntryScreen> createState() => _CodeEntryScreenState();
}

class _CodeEntryScreenState extends State<CodeEntryScreen> {
  final codeController = TextEditingController();
  String kind = 'DEVICE';

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final c = context.read<AccountController>();
    final value = normalizeAccountCode(codeController.text);
    if (value.isEmpty) return;
    final effectiveKind = detectAccountCodeKind(value, fallback: kind);
    if (effectiveKind == 'DEVICE') {
      await c.action(() => c.pair(value));
      if (mounted && c.error == null) Navigator.pop(context);
      return;
    }
    if (effectiveKind == 'ATTENDANCE') {
      await c.action(() async {
        await c.api.call('/attendance/check-in',
            method: 'POST', child: true, body: {'token': value});
      });
      if (mounted && c.error == null) Navigator.pop(context);
      return;
    }
    if (c.guardian == null) {
      if (effectiveKind == 'MOSQUE') c.rememberInvitation(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(localized(
                context, 'سجّل الدخول أو أنشئ حسابًا لإكمال الدعوة.'))));
        Navigator.pop(context);
      }
      return;
    }
    if (effectiveKind == 'FAMILY') {
      await c.action(() async {
        await c.api.call('/family-invitations/redeem',
            method: 'POST', body: {'token': value});
      });
      if (mounted && c.error == null) Navigator.pop(context);
      return;
    }
    c.rememberInvitation(value);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MosqueJoinScreen(initialToken: value)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AccountController>();
    return Scaffold(
      appBar: AppBar(title: Text(localized(context, 'استخدام رمز'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration:
                    InputDecoration(labelText: localized(context, 'نوع الرمز')),
                items: [
                  DropdownMenuItem(
                      value: 'DEVICE',
                      child: Text(localized(context, 'ربط جهاز طفل'))),
                  DropdownMenuItem(
                      value: 'MOSQUE',
                      child: Text(localized(context, 'دعوة مجموعة مسجد'))),
                  DropdownMenuItem(
                      value: 'FAMILY',
                      child: Text(localized(context, 'دعوة أسرة'))),
                  DropdownMenuItem(
                      value: 'ATTENDANCE',
                      child: Text(localized(context, 'تسجيل حضور في المسجد'))),
                ],
                onChanged: (value) => setState(() => kind = value ?? 'DEVICE'),
              ),
              TextField(
                controller: codeController,
                textDirection: TextDirection.ltr,
                decoration:
                    InputDecoration(labelText: localized(context, 'الرمز')),
              ),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: c.busy ? null : submit,
                  child: Text(localized(context, 'متابعة'))),
              OutlinedButton.icon(
                onPressed: c.busy
                    ? null
                    : () async {
                        final value = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                                builder: (_) => const PairScanner()));
                        if (value != null && mounted) {
                          final normalized = normalizeAccountCode(value);
                          codeController.text = normalized;
                          kind =
                              detectAccountCodeKind(normalized, fallback: kind);
                          setState(() {});
                          if (kind == 'DEVICE') await submit();
                        }
                      },
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(localized(context, 'مسح QR')),
              ),
              if (c.error != null)
                Text(localized(context, c.error!),
                    style: const TextStyle(color: AppColors.warning)),
            ],
          ),
        ),
      ),
    );
  }
}

class PairScanner extends StatefulWidget {
  const PairScanner({super.key});

  @override
  State<PairScanner> createState() => _PairScannerState();
}

class _PairScannerState extends State<PairScanner> {
  final scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool found = false;

  @override
  void dispose() {
    unawaited(scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(localized(context, 'مسح الرمز'))),
        body: Column(
          children: [
            const AppNote(
                'اسمح بالكاميرا لمسح QR فقط. يمكنك دائمًا إدخال الرمز يدويًا.'),
            Expanded(
              child: MobileScanner(
                controller: scanner,
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(localized(
                        context, 'تعذر فتح الكاميرا. أدخل الرمز يدويًا.')),
                  ),
                ),
                onDetect: (capture) {
                  if (found) return;
                  for (final barcode in capture.barcodes) {
                    final text = barcode.rawValue;
                    if (text != null &&
                        (normalizeAccountCode(text).startsWith('iqtadi-'))) {
                      found = true;
                      Navigator.pop(context, normalizeAccountCode(text));
                      break;
                    }
                  }
                },
              ),
            ),
          ],
        ),
      );
}
