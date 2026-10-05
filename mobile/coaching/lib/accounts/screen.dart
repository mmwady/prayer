import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import 'controller.dart';

class AccountEntry extends StatelessWidget {
  const AccountEntry({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AccountController?>();
    if (c == null) return const SizedBox.shrink();
    return AppCard(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AccountScreen())),
      child: ListTile(
          leading: const Icon(Icons.family_restroom, color: AppColors.accent),
          title: Text(c.child == null
              ? 'الحساب والمتابعة — اختياري'
              : 'السلام عليكم يا ${c.child!['name']}'),
          subtitle: Text(c.child != null
              ? 'التحليل على جهازك • ${c.queue.length} نتيجة تنتظر المزامنة'
              : 'ولي أمر أو معلم؟ تابع النتائج النهائية فقط'),
          trailing: const Icon(Icons.chevron_left)),
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController(),
      _code = TextEditingController();
  bool signup = false;
  String role = 'PARENT';
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final c in [_email, _password, _name, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AccountController>();
    return Scaffold(
        appBar: AppBar(title: const Text('الحساب والمتابعة')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      const AppNote(
                          'تحليل الصلاة محلي على جهازك. تصل ملخصات النتائج فقط عند ربط الجهاز. الحساب اختياري؛ التدريب متاح دون إنترنت.'),
                      if (!c.ready || c.busy) const LinearProgressIndicator(),
                      if (c.error != null)
                        Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(c.error!,
                                style:
                                    const TextStyle(color: AppColors.warning))),
                      if (c.child != null) ...[
                        Text('السلام عليكم يا ${c.child!['name']}',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text('${c.queue.length} نتيجة محفوظة تنتظر المزامنة'),
                        const AppNote(
                            'نتيجة الفيديو تُسجل بوقت انتهاء التحليل، وليس وقت تصوير الفيديو القديم. النتائج غير المؤكدة تظهر للمراجعة ولا تُحتسب كنجاح.'),
                        FilledButton.icon(
                            onPressed: c.syncing ? null : c.sync,
                            icon: const Icon(Icons.sync),
                            label: const Text('مزامنة النتائج')),
                        TextButton(
                            onPressed: c.busy || c.syncing
                                ? null
                                : () => c.action(c.disconnect),
                            child: const Text('فصل هذا الجهاز')),
                      ] else ...[
                        const SectionTitle('ربط جهاز طفل / طالب',
                            icon: Icons.qr_code_scanner),
                        TextField(
                            controller: _code,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                                labelText: 'رمز الربط المؤقت',
                                helperText:
                                    'أدخل الرمز المعروض عند ولي الأمر أو المعلم')),
                        Wrap(spacing: 12, children: [
                          FilledButton(
                              onPressed: c.busy
                                  ? null
                                  : () => c.action(() => c.pair(_code.text)),
                              child: const Text('ربط الجهاز')),
                          OutlinedButton.icon(
                              onPressed: c.busy
                                  ? null
                                  : () async {
                                      final value = await Navigator.of(context)
                                          .push<String>(MaterialPageRoute(
                                              builder: (_) =>
                                                  const PairScanner()));
                                      if (value != null && mounted) {
                                        _code.text = value;
                                        await c.action(() => c.pair(value));
                                      }
                                    },
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('مسح QR')),
                        ]),
                        const AppNote(
                            'إدخال الرمز متاح دائمًا على الويب إذا لم تدعم الكاميرا المسح.'),
                      ],
                      const SizedBox(height: 24),
                      if (c.guardian != null) ...[
                        Text('مرحبًا ${c.guardian!['name']}',
                            style: Theme.of(context).textTheme.titleLarge),
                        FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const DashboardScreen())),
                            icon: const Icon(Icons.dashboard_outlined),
                            label: const Text('لوحة المتابعة')),
                        TextButton(
                            onPressed: c.busy ? null : () => c.action(c.logout),
                            child: const Text('تسجيل الخروج')),
                      ] else
                        Form(
                            key: form,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SectionTitle(
                                      signup
                                          ? 'إنشاء حساب'
                                          : 'دخول ولي أمر / معلم',
                                      icon: Icons.person_outline),
                                  if (signup)
                                    TextFormField(
                                        controller: _name,
                                        decoration: const InputDecoration(
                                            labelText: 'الاسم الكامل'),
                                        validator: (v) =>
                                            (v?.trim().isEmpty ?? true)
                                                ? 'أدخل الاسم'
                                                : null),
                                  TextFormField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      textDirection: TextDirection.ltr,
                                      decoration: const InputDecoration(
                                          labelText: 'البريد الإلكتروني'),
                                      validator: (v) =>
                                          v != null && v.contains('@')
                                              ? null
                                              : 'أدخل بريدًا صالحًا'),
                                  TextFormField(
                                      controller: _password,
                                      obscureText: true,
                                      textDirection: TextDirection.ltr,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'كلمة المرور (10 أحرف على الأقل)'),
                                      validator: (v) => (v?.length ?? 0) >= 10
                                          ? null
                                          : '10 أحرف على الأقل'),
                                  if (signup)
                                    DropdownButtonFormField<String>(
                                        initialValue: role,
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'PARENT',
                                              child: Text('ولي أمر')),
                                          DropdownMenuItem(
                                              value: 'TEACHER',
                                              child: Text('معلم'))
                                        ],
                                        onChanged: (v) =>
                                            setState(() => role = v!)),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                      onPressed: c.busy || !c.ready
                                          ? null
                                          : () {
                                              if (form.currentState!
                                                  .validate()) {
                                                c.action(() => c.authenticate(
                                                    _email.text,
                                                    _password.text,
                                                    role,
                                                    fullName: signup
                                                        ? _name.text
                                                        : null));
                                              }
                                            },
                                      child: Text(signup
                                          ? 'إنشاء الحساب وإرسال رابط التفعيل'
                                          : 'تسجيل الدخول')),
                                  TextButton(
                                      onPressed: () =>
                                          setState(() => signup = !signup),
                                      child: Text(signup
                                          ? 'لدي حساب بالفعل'
                                          : 'إنشاء حساب جديد')),
                                  TextButton(
                                      onPressed: c.busy
                                          ? null
                                          : () => c.action(
                                              () => c.recover(_email.text)),
                                      child: const Text('نسيت كلمة المرور')),
                                  TextButton(
                                      onPressed: c.busy
                                          ? null
                                          : () => c.action(() =>
                                              c.resendVerification(
                                                  _email.text, _password.text)),
                                      child: const Text(
                                          'إعادة إرسال رابط التفعيل')),
                                ])),
                    ]))));
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
      appBar: AppBar(title: const Text('مسح رمز الربط')),
      body: Column(children: [
        const AppNote(
            'اسمح بالكاميرا لمسح QR فقط. إذا تعذر المسح، ارجع وأدخل الرمز يدويًا.'),
        Expanded(
            child: MobileScanner(
                controller: scanner,
                errorBuilder: (context, error) => const Center(
                        child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                          'تعذر فتح ماسح الكاميرا. ارجع وأدخل رمز الربط يدويًا.'),
                    )),
                onDetect: (capture) {
                  if (found) return;
                  for (final b in capture.barcodes) {
                    final text = b.rawValue;
                    if (text != null && text.startsWith('iqtadi-pair:')) {
                      found = true;
                      Navigator.pop(context, text);
                      break;
                    }
                  }
                }))
      ]));
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> groups = [];
  Map<String, dynamic>? dashboard;
  String? selected, error;
  bool loading = false;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      load();
      _poll = Timer.periodic(const Duration(seconds: 30), (_) => load());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (loading || !mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<AccountController>().api;
      groups = (await api.call('/groups') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!groups.any((g) => g['id'] == selected)) {
        selected = groups.isEmpty ? null : groups.first['id'];
      }
      dashboard = selected == null
          ? null
          : Map<String, dynamic>.from(
              await api.call('/groups/$selected/progress'));
    } catch (e) {
      error = 'تعذر تحديث اللوحة. تحقق من الاتصال. $e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> run(Future<void> Function() work) async {
    await context.read<AccountController>().action(work);
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AccountController>();
    final children = dashboard?['children'] as List? ?? [];
    return Scaffold(
        appBar: AppBar(title: const Text('لوحة المتابعة'), actions: [
          IconButton(onPressed: load, icon: const Icon(Icons.refresh))
        ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1050),
                child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      Text('مرحبًا ${c.guardian?['name'] ?? ''}',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const AppNote(
                          'النقاط لتشجيع اكتمال الحركات المرصودة؛ ليست حكمًا على صحة الصلاة. +5 لكل صلاة مؤكدة و+2 للتوقيت و+3 ليوم مكتمل. لا خصم ولا نقاط إضافية لتكرار المحاولات.'),
                      if (loading) const LinearProgressIndicator(),
                      if (error != null || c.error != null)
                        Text(error ?? c.error!,
                            style: const TextStyle(color: AppColors.warning)),
                      if (groups.isNotEmpty)
                        DropdownButtonFormField<String>(
                            key: ValueKey(selected),
                            initialValue: selected,
                            isExpanded: true,
                            items: [
                              for (final g in groups)
                                DropdownMenuItem(
                                    value: g['id'], child: Text(g['name']))
                            ],
                            onChanged: (v) {
                              selected = v;
                              load();
                            }),
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: c.busy ? null : () => groupForm(),
                            icon: const Icon(Icons.group_add_outlined),
                            label: Text(c.guardian?['role'] == 'TEACHER'
                                ? 'إضافة فصل'
                                : 'إضافة أسرة')),
                        if (selected != null)
                          OutlinedButton.icon(
                              onPressed: c.busy
                                  ? null
                                  : () => groupForm(
                                      existing: groups.firstWhere(
                                          (g) => g['id'] == selected)),
                              icon: const Icon(Icons.schedule),
                              label: const Text('إعداد مواقيت المجموعة')),
                        if (selected != null)
                          FilledButton.icon(
                              onPressed: c.busy ? null : () => childForm(),
                              icon: const Icon(Icons.person_add_alt),
                              label: const Text('إضافة طفل / طالب')),
                      ]),
                      if (dashboard != null) ...[
                        SectionTitle('متابعة اليوم ${dashboard!['date']}',
                            icon: Icons.today),
                        if ((dashboard!['group']['schedule'] as Map).isEmpty)
                          const AppNote(
                              'لم تُحدد مواقيت بعد. النتائج تُحتسب دون مكافأة توقيت؛ الصلاة غير المسجلة لا تُعتبر فائتة دون جدول.'),
                        for (final child in children)
                          AppCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                        child: Text((child['name'] as String)
                                            .characters
                                            .first)),
                                    title: Text(child['name']),
                                    subtitle: Text(
                                        '${child['valid_prayers']}/5 • ${child['points']} نقطة اليوم • سلسلة ${child['streak']} أيام مكتملة')),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final prayer in _prayers.entries)
                                    Tooltip(
                                        message:
                                            _state(child['states'][prayer.key]),
                                        child: Chip(
                                            label: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                              Icon(
                                                  _stateIcon(child['states']
                                                      [prayer.key]),
                                                  size: 18,
                                                  color: _stateColor(
                                                      child['states']
                                                          [prayer.key])),
                                              const SizedBox(
                                                  width: AppSpacing.xs),
                                              Text(prayer.value),
                                            ])))
                                ]),
                                Wrap(spacing: 8, children: [
                                  TextButton.icon(
                                      onPressed:
                                          c.busy ? null : () => pairing(child),
                                      icon: const Icon(Icons.qr_code),
                                      label: const Text('ربط جهاز')),
                                  TextButton.icon(
                                      onPressed: () => devices(child),
                                      icon: const Icon(Icons.devices),
                                      label: const Text('الأجهزة')),
                                  TextButton(
                                      onPressed: () => childForm(
                                          existing:
                                              Map<String, dynamic>.from(child)),
                                      child: const Text('تعديل / إيقاف')),
                                  TextButton(
                                      onPressed: () => history(child),
                                      child: const Text('الأسبوع')),
                                ])
                              ])),
                        const SectionTitle('ترتيب الأسبوع — آخر 7 أيام',
                            icon: Icons.emoji_events_outlined),
                        for (final child in dashboard!['leaderboard'])
                          AppCard(
                              child: ListTile(
                                  title: Text(child['name']),
                                  trailing:
                                      Text('${child['weekly_points']} نقطة'),
                                  subtitle: Text(
                                      '${child['weekly_valid_prayers']} صلاة مؤكدة • ${child['weekly_on_time_prayers']} في الوقت • سلسلة ${child['streak']} أيام'))),
                        const AppNote(
                            'اضغط مطولًا على رمز الصلاة لمعرفة الحالة. الأخضر: مكتملة في الوقت، الساعة: متأخرة، النجمة: التوقيت غير معروف، علامة السؤال: تحتاج مراجعة، الساعة الرملية: لم ينتهِ الوقت / لم يحدد. سلسلة الأيام: خمس صلوات مؤكدة يوميًا.'),
                      ] else if (!loading)
                        const AppNote(
                            'ابدأ بإضافة أسرة أو فصل، ثم الطفل، ثم اربط جهازه. تجربة الصلاة المحلية تظل متاحة للجميع.'),
                    ]))));
  }

  static const _prayers = {
    'fajr': 'الفجر',
    'dhuhr': 'الظهر',
    'asr': 'العصر',
    'maghrib': 'المغرب',
    'isha': 'العشاء'
  };
  static String _state(dynamic value) =>
      {
        'ON_TIME': 'مكتملة في الوقت',
        'LATE': 'مكتملة خارج الوقت',
        'CORRECT_TIMING_UNKNOWN': 'مكتملة والتوقيت غير معروف',
        'UNCERTAIN': 'تحتاج إلى مراجعة',
        'INCOMPLETE': 'غير مكتملة',
        'PENDING': 'لم ينتهِ الوقت أو لم يحدد',
        'NO_ATTEMPT': 'لا محاولة بعد نهاية الوقت'
      }[value] ??
      '—';
  static IconData _stateIcon(dynamic value) => switch (value) {
        'ON_TIME' => Icons.check_circle_outline,
        'LATE' => Icons.schedule,
        'CORRECT_TIMING_UNKNOWN' => Icons.star_outline,
        'UNCERTAIN' => Icons.help_outline,
        'INCOMPLETE' => Icons.cancel_outlined,
        'PENDING' => Icons.hourglass_empty,
        _ => Icons.remove,
      };
  static Color _stateColor(dynamic value) => switch (value) {
        'ON_TIME' || 'CORRECT_TIMING_UNKNOWN' => AppColors.accent,
        'LATE' || 'UNCERTAIN' => AppColors.warning,
        'INCOMPLETE' => AppColors.danger,
        _ => AppColors.textSecondary,
      };

  Future<void> groupForm({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing?['name'] ?? ''),
        tz = TextEditingController(
            text: existing?['timezone'] ?? 'Africa/Cairo');
    final schedule = existing?['schedule'] as Map? ?? {};
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final from = TextEditingController(text: schedule['from'] ?? today),
        until = TextEditingController(text: schedule['until'] ?? today);
    final clocks = {
      for (final key in ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'])
        key: TextEditingController(text: schedule[key] ?? '')
    };
    bool timing = schedule.isNotEmpty;
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (dialog, update) => AlertDialog(
                    title: Text(
                        existing == null ? 'مجموعة جديدة' : 'إعدادات المجموعة'),
                    content: SizedBox(
                        width: 440,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: name,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'اسم الأسرة / الفصل / المدينة')),
                              TextField(
                                  controller: tz,
                                  textDirection: TextDirection.ltr,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'المنطقة الزمنية (مثل Africa/Cairo)')),
                              SwitchListTile(
                                  value: timing,
                                  title:
                                      const Text('مواقيت معتمدة لهذه الفترة'),
                                  onChanged: (v) => update(() => timing = v)),
                              if (timing) ...[
                                const Text(
                                    'أدخل جدول المدينة المعتمد، HH:MM بنظام 24 ساعة. مدة أقصاها 32 يومًا. خارجها يكون التوقيت غير معروف.'),
                                TextField(
                                    controller: from,
                                    textDirection: TextDirection.ltr,
                                    decoration: const InputDecoration(
                                        labelText: 'من YYYY-MM-DD')),
                                TextField(
                                    controller: until,
                                    textDirection: TextDirection.ltr,
                                    decoration: const InputDecoration(
                                        labelText: 'حتى YYYY-MM-DD')),
                                for (final e in clocks.entries)
                                  TextField(
                                      controller: e.value,
                                      textDirection: TextDirection.ltr,
                                      decoration: InputDecoration(
                                          labelText:
                                              '${_prayers[e.key] ?? 'الشروق'} HH:MM')),
                              ]
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('حفظ'))
                    ])));
    if (ok == true && mounted) {
      await run(() async {
        await context.read<AccountController>().api.call(
            existing == null ? '/groups' : '/groups/${existing['id']}',
            method: existing == null ? 'POST' : 'PUT',
            body: {
              'name': name.text.trim(),
              'timezone': tz.text.trim(),
              'schedule': timing
                  ? {
                      'from': from.text.trim(),
                      'until': until.text.trim(),
                      for (final e in clocks.entries) e.key: e.value.text.trim()
                    }
                  : null
            });
      });
    }
    for (final controller in [name, tz, from, until, ...clocks.values]) {
      controller.dispose();
    }
  }

  Future<void> childForm({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing?['name'] ?? ''),
        age = TextEditingController(text: '${existing?['age'] ?? 11}');
    bool active = true;
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (dialog, update) => AlertDialog(
                    title: const Text('طفل / طالب'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'الاسم')),
                      TextField(
                          controller: age,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'العمر (3–25)')),
                      if (existing != null)
                        SwitchListTile(
                            value: active,
                            title: const Text('ملف نشط'),
                            subtitle: const Text('الإيقاف يفصل كل الأجهزة'),
                            onChanged: (v) => update(() => active = v))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('حفظ'))
                    ])));
    if (ok == true && mounted) {
      await run(() async {
        await context.read<AccountController>().api.call(
            existing == null
                ? '/groups/$selected/children'
                : '/children/${existing['id']}',
            method: existing == null ? 'POST' : 'PUT',
            body: {
              'name': name.text.trim(),
              'age': int.tryParse(age.text) ?? 0,
              'active': active
            });
      });
    }
    name.dispose();
    age.dispose();
  }

  Future<void> pairing(Map child) async {
    await run(() async {
      final pair = await context
          .read<AccountController>()
          .api
          .call('/children/${child['id']}/pairing', method: 'POST') as Map;
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: Text('ربط جهاز ${child['name']}'),
                  content: SizedBox(
                      width: 300,
                      child: SingleChildScrollView(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                        QrImageView(data: pair['qr_payload'], size: 240),
                        SelectableText(pair['code'],
                            textDirection: TextDirection.ltr,
                            style: Theme.of(dialog).textTheme.headlineSmall),
                        const Text(
                            'صالح 5 دقائق ولمرة واحدة فقط. لا تشارك الرمز مع غير الطفل.'),
                        Text(
                            'ينتهي: ${DateTime.parse(pair['expires_at']).toLocal()}')
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('إغلاق'))
                  ]));
    });
  }

  Future<void> devices(Map child) async {
    await run(() async {
      final rows = await context
          .read<AccountController>()
          .api
          .call('/children/${child['id']}/devices') as List;
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: Text('أجهزة ${child['name']}'),
                  content: SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (rows.isEmpty) const Text('لا أجهزة مرتبطة'),
                        for (final d in rows)
                          ListTile(
                              title: Text(d['platform']),
                              subtitle: Text(d['revoked_at'] != null
                                  ? 'مفصول'
                                  : 'آخر اتصال: ${DateTime.fromMillisecondsSinceEpoch((d['last_seen_at'] * 1000).round()).toLocal()}'),
                              trailing: d['revoked_at'] != null
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.link_off),
                                      onPressed: () async {
                                        Navigator.pop(dialog);
                                        await run(() async {
                                          await context
                                              .read<AccountController>()
                                              .api
                                              .call(
                                                  '/children/${child['id']}/devices/${d['id']}',
                                                  method: 'DELETE');
                                        });
                                      }))
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('إغلاق'))
                  ]));
    });
  }

  void history(Map child) => showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
              title: Text('أسبوع ${child['name']}'),
              content: SizedBox(
                  width: 400,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final d in child['week'])
                      ListTile(
                          title: Text(d['date']),
                          subtitle: Text(
                              '${d['valid_prayers']}/5 • ${d['on_time_prayers']} في الوقت'),
                          trailing: Text('${d['points']} نقطة'))
                  ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('إغلاق'))
              ]));
}
