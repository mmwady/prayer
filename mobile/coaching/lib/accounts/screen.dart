import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import 'controller.dart';
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
        title: Text(signedIn
            ? 'مرحبًا ${c.guardian!['name']}'
            : dependent
                ? 'جهاز ${c.child!['name']}'
                : 'الحساب — اختياري'),
        subtitle: Text(signedIn
            ? 'تقدمي • أسرتي • مجموعات المسجد'
            : dependent
                ? 'التدريب المحلي مرتبط بهذا الملف'
                : 'تسجيل موحّد للجميع دون اختيار دور دائم'),
        trailing: const Icon(Icons.chevron_left),
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
      appBar: AppBar(title: const Text('الحساب')),
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
                  child: Text(c.error!,
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
                decoration: const InputDecoration(labelText: 'الاسم'),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'أدخل الاسم' : null,
              ),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
              validator: (value) => value != null && value.contains('@')
                  ? null
                  : 'أدخل بريدًا صالحًا',
            ),
            TextFormField(
              controller: password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText: 'كلمة المرور (8 أحرف على الأقل)'),
              validator: (value) =>
                  (value?.length ?? 0) >= 8 ? null : '8 أحرف على الأقل',
            ),
            if (signup) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: learningStage,
                decoration:
                    const InputDecoration(labelText: 'مسار التعلّم — اختياري'),
                items: const [
                  DropdownMenuItem(value: 'GENERAL', child: Text('تعلّم عام')),
                  DropdownMenuItem(
                      value: 'NEW_MUSLIM', child: Text('مسلم جديد')),
                ],
                onChanged: (value) =>
                    setState(() => learningStage = value ?? 'GENERAL'),
              ),
              DropdownButtonFormField<String>(
                initialValue: accessibilityMode,
                decoration:
                    const InputDecoration(labelText: 'طريقة العرض — اختيارية'),
                items: const [
                  DropdownMenuItem(
                      value: 'STANDARD', child: Text('العرض القياسي')),
                  DropdownMenuItem(value: 'SIMPLE', child: Text('واجهة مبسطة')),
                  DropdownMenuItem(value: 'LARGE_TEXT', child: Text('نص أكبر')),
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
              child: Text(signup ? 'إنشاء الحساب' : 'تسجيل الدخول'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CodeEntryScreen())),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('لدي رمز دعوة أو ربط جهاز'),
            ),
            TextButton(
              onPressed: () => setState(() => signup = !signup),
              child: Text(signup ? 'لدي حساب بالفعل' : 'إنشاء حساب جديد'),
            ),
            if (!signup) ...[
              TextButton(
                onPressed:
                    c.busy ? null : () => c.action(() => c.recover(email.text)),
                child: const Text('نسيت كلمة المرور'),
              ),
              TextButton(
                onPressed: c.busy
                    ? null
                    : () => c.action(
                        () => c.resendVerification(email.text, password.text)),
                child: const Text('إعادة إرسال رابط التفعيل'),
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
            label: const Text('العودة إلى التدريب'),
          ),
          OutlinedButton.icon(
            onPressed: c.busy ? null : () => c.action(c.disconnect),
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل خروج الطفل من هذا الجهاز'),
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
          title: const Text('جارٍ تحميل النتيجة'),
          trailing: IconButton(
            tooltip: 'تحديث النتيجة',
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
            title: Text('${score['weekly_points'] ?? 0} نقطة هذا الأسبوع'),
            subtitle: Text(
                '${score['weekly_valid_prayers'] ?? 0} صلاة مكتملة • ${score['streak'] ?? 0} أيام متتالية'),
            trailing: IconButton(
              tooltip: 'تحديث النتيجة',
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
          Text('اليوم: ${score['valid_prayers'] ?? 0} من 5 صلوات مكتملة'),
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
                subtitle: Text(enabled
                    ? 'الاسم: ${row['alias']} • ${row['weekly_points'] ?? 0} نقطة'
                    : 'ولي الأمر عطّل الظهور في لوحة الترتيب.'),
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
          Text('السلام عليكم، ${c.guardian!['name']}',
              style: Theme.of(context).textTheme.headlineSmall),
          if (c.pendingInvitation != null)
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.mark_email_unread_outlined,
                    color: AppColors.accent),
                title: const Text('دعوة مسجد بانتظار الإكمال'),
                subtitle: const Text('اختر ملفك أو طفلك ثم وافق على المشاركة.'),
                trailing: FilledButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MosqueJoinScreen(
                          initialToken: c.pendingInvitation!))),
                  child: const Text('إكمال'),
                ),
              ),
            ),
          AppCard(
            child: ListTile(
              leading:
                  const Icon(Icons.self_improvement, color: AppColors.accent),
              title: const Text('تقدمي الشخصي'),
              subtitle: Text(c.child?['profile_kind'] == 'SELF'
                  ? 'نتائج التدريب بالكاميرا مرتبطة بحسابك'
                  : 'اختر ملفك الشخصي لمزامنة ملخصات التدريب'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          AppCard(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FamilyScreen())),
            child: const ListTile(
              leading: Icon(Icons.family_restroom, color: AppColors.accent),
              title: Text('أسرتي'),
              subtitle: Text('أفراد الأسرة • الأطفال • الأجهزة • الموافقات'),
              trailing: Icon(Icons.chevron_left),
            ),
          ),
          AppCard(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MosqueGroupsScreen())),
            child: const ListTile(
              leading: Icon(Icons.groups_outlined, color: AppColors.accent),
              title: Text('مجموعات المسجد'),
              subtitle: Text('الانضمام بموافقة ولي الأمر • الحضور • التشجيع'),
              trailing: Icon(Icons.chevron_left),
            ),
          ),
          AppCard(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MosqueAccessScreen())),
            child: const ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined,
                  color: AppColors.accent),
              title: Text('صلاحيات وإدارة المسجد'),
              subtitle: Text('طلب صلاحية قائد • متابعة التحقق • إدارة الطلبات للمسؤول العام'),
              trailing: Icon(Icons.chevron_left),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MosqueJoinScreen(target: 'SELF'))),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('مسح QR والانضمام بنفسي'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MosqueJoinScreen(target: 'CHILD'))),
            icon: const Icon(Icons.child_care),
            label: const Text('مسح QR وضم طفل بموافقتي'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CodeEntryScreen())),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('استخدام رمز دعوة أو حضور أو جهاز'),
          ),
          if (c.child != null) _linkedProfile(c),
          TextButton(
            onPressed: c.busy ? null : () => c.action(c.logout),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      );

  Widget _linkedProfile(AccountController c) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text('ملف التدريب: ${c.child!['name']}'),
              subtitle: Text('${c.queue.length} نتيجة تنتظر المزامنة'),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: c.syncing ? null : c.sync,
                  icon: const Icon(Icons.sync),
                  label: const Text('مزامنة'),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('سجّل الدخول أو أنشئ حسابًا لإكمال الدعوة.')));
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
      appBar: AppBar(title: const Text('استخدام رمز')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'نوع الرمز'),
                items: const [
                  DropdownMenuItem(
                      value: 'DEVICE', child: Text('ربط جهاز طفل')),
                  DropdownMenuItem(
                      value: 'MOSQUE', child: Text('دعوة مجموعة مسجد')),
                  DropdownMenuItem(value: 'FAMILY', child: Text('دعوة أسرة')),
                  DropdownMenuItem(
                      value: 'ATTENDANCE', child: Text('تسجيل حضور في المسجد')),
                ],
                onChanged: (value) => setState(() => kind = value ?? 'DEVICE'),
              ),
              TextField(
                controller: codeController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'الرمز'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: c.busy ? null : submit,
                  child: const Text('متابعة')),
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
                label: const Text('مسح QR'),
              ),
              if (c.error != null)
                Text(c.error!,
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
        appBar: AppBar(title: const Text('مسح الرمز')),
        body: Column(
          children: [
            const AppNote(
                'اسمح بالكاميرا لمسح QR فقط. يمكنك دائمًا إدخال الرمز يدويًا.'),
            Expanded(
              child: MobileScanner(
                controller: scanner,
                errorBuilder: (context, error) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text('تعذر فتح الكاميرا. أدخل الرمز يدويًا.'),
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
