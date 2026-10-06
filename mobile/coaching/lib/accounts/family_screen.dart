import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import 'client.dart';
import 'controller.dart';
import 'movement_progress.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  List<Map<String, dynamic>> families = [];
  Map<String, dynamic>? detail;
  Map<String, dynamic>? progress;
  String? selectedId;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load([String? familyId]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<AccountController>().api;
      final rows = (await api.call('/families') as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final nextId = familyId ??
          selectedId ??
          (rows.isEmpty ? null : rows.first['id'] as String);
      Map<String, dynamic>? nextDetail;
      Map<String, dynamic>? nextProgress;
      if (nextId != null) {
        nextDetail =
            Map<String, dynamic>.from(await api.call('/families/$nextId'));
        final family = Map<String, dynamic>.from(nextDetail['family'] as Map);
        if (family['role'] == 'OWNER' || family['role'] == 'GUARDIAN') {
          final dependents = (nextDetail['dependents'] as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
          await Future.wait(dependents.map((child) async {
            child['devices'] =
                await api.call('/children/${child['id']}/devices');
          }));
          nextDetail['dependents'] = dependents;
        }
        nextProgress = Map<String, dynamic>.from(
            await api.call('/families/$nextId/progress'));
      }
      if (!mounted) return;
      setState(() {
        families = rows;
        selectedId = nextId;
        detail = nextDetail;
        progress = nextProgress;
      });
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _message(Object exception) => exception is AccountError
      ? exception.toString()
      : 'تعذر تحميل بيانات الأسرة. حاول مجددًا.';

  Future<void> _createFamily() async {
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنشاء أسرة'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم الأسرة'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إنشاء')),
        ],
      ),
    );
    final value = name.text.trim();
    name.dispose();
    if (accepted != true || value.isEmpty || !mounted) return;
    await _run(() async {
      final result = await context.read<AccountController>().api.call(
          '/families',
          method: 'POST',
          body: {'name': value, 'timezone': 'Asia/Riyadh'}) as Map;
      await load(result['id'] as String);
    });
  }

  Future<void> _addDependent() async {
    final name = TextEditingController();
    final alias = TextEditingController();
    var ageBand = 'CHILD_5_9';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة طفل إلى الأسرة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'الاسم الحقيقي'),
                ),
                TextField(
                  controller: alias,
                  decoration: const InputDecoration(
                      labelText: 'الاسم المستعار للمجموعات — اختياري'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: ageBand,
                  decoration: const InputDecoration(labelText: 'الفئة العمرية'),
                  items: const [
                    DropdownMenuItem(
                        value: 'CHILD_5_9', child: Text('5–9 سنوات')),
                    DropdownMenuItem(
                        value: 'CHILD_10_13', child: Text('10–13 سنة')),
                    DropdownMenuItem(
                        value: 'TEEN_14_17', child: Text('14–17 سنة')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => ageBand = value ?? ageBand),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('إضافة')),
          ],
        ),
      ),
    );
    final childName = name.text.trim();
    final childAlias = alias.text.trim();
    name.dispose();
    alias.dispose();
    if (accepted != true ||
        childName.isEmpty ||
        selectedId == null ||
        !mounted) {
      return;
    }
    await _run(() async {
      await context.read<AccountController>().api.call(
        '/families/$selectedId/dependents',
        method: 'POST',
        body: {
          'name': childName,
          'age_band': ageBand,
          if (childAlias.isNotEmpty) 'alias': childAlias,
        },
      );
      await load(selectedId);
    });
  }

  Future<void> _inviteMember() async {
    var role = 'GUARDIAN';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('دعوة فرد إلى الأسرة'),
          content: DropdownButtonFormField<String>(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'مستوى الصلاحية'),
            items: const [
              DropdownMenuItem(
                  value: 'GUARDIAN',
                  child: Text('ولي أمر — إدارة الأطفال والموافقات')),
              DropdownMenuItem(
                  value: 'ADULT', child: Text('بالغ — تقدمه الشخصي فقط')),
              DropdownMenuItem(
                  value: 'SUPPORTER', child: Text('داعم — متابعة محدودة')),
            ],
            onChanged: (value) =>
                setDialogState(() => role = value ?? 'GUARDIAN'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('إنشاء الدعوة')),
          ],
        ),
      ),
    );
    if (accepted != true || selectedId == null || !mounted) return;
    await _run(() async {
      final invite = Map<String, dynamic>.from(
          await context.read<AccountController>().api.call(
        '/families/$selectedId/invites',
        method: 'POST',
        body: {'role': role},
      ));
      if (mounted) await _showQr('دعوة الأسرة', invite);
    });
  }

  Future<void> _manageMember(Map member) async {
    var role = member['role'] as String;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('صلاحيات ${member['name']}'),
          content: DropdownButtonFormField<String>(
            initialValue: role,
            decoration:
                const InputDecoration(labelText: 'الدور داخل هذه الأسرة فقط'),
            items: const [
              DropdownMenuItem(
                  value: 'GUARDIAN',
                  child: Text('ولي أمر — إدارة الأطفال والموافقات')),
              DropdownMenuItem(
                  value: 'ADULT', child: Text('بالغ — ملفه الشخصي فقط')),
              DropdownMenuItem(
                  value: 'SUPPORTER', child: Text('داعم — مشاهدة محدودة')),
            ],
            onChanged: (value) => setDialogState(() => role = value ?? role),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'REMOVE'),
                child: const Text('إزالة من الأسرة')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, role),
                child: const Text('حفظ الصلاحية')),
          ],
        ),
      ),
    );
    if (result == null || selectedId == null || !mounted) return;
    await _run(() async {
      final path = '/families/$selectedId/members/${member['id']}';
      if (result == 'REMOVE') {
        await context
            .read<AccountController>()
            .api
            .call(path, method: 'DELETE');
      } else {
        await context
            .read<AccountController>()
            .api
            .call(path, method: 'PUT', body: {'role': result});
      }
      await load(selectedId);
    });
  }

  Future<void> _pairDevice(Map<String, dynamic> dependent) async {
    await _run(() async {
      final invite = Map<String, dynamic>.from(
          await context.read<AccountController>().api.call(
                '/children/${dependent['id']}/pairing',
                method: 'POST',
              ));
      if (mounted) {
        await _showQr('ربط جهاز ${dependent['name']}', invite,
            note:
                'افتح كاميرا هاتف الطفل وامسح الرمز. سيتم الربط مباشرة دون بريد أو كلمة مرور، ويبقى الجهاز مرتبطًا حتى تفصله من هنا. ينتهي الرمز خلال 5 دقائق ويُستخدم مرة واحدة.');
      }
    });
  }

  Future<void> _showQr(String title, Map<String, dynamic> invite,
          {String? note}) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                    data: (invite['qr_url'] ?? invite['qr_payload']) as String,
                    size: 220),
                const SizedBox(height: 12),
                SelectableText(invite['code'] as String,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (note != null) ...[
                  const SizedBox(height: 8),
                  Text(note, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('تم')),
          ],
        ),
      );

  Future<void> _manageDevices(Map<String, dynamic> dependent) async {
    setState(() {
      loading = true;
      error = null;
    });
    List<Map<String, dynamic>> devices;
    try {
      devices = (await context
              .read<AccountController>()
              .api
              .call('/children/${dependent['id']}/devices') as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .where((device) => device['revoked_at'] == null)
          .toList();
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
      return;
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (!mounted) return;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('أجهزة ${dependent['name']}'),
        content: SizedBox(
          width: 440,
          child: devices.isEmpty
              ? const Text(
                  'لا يوجد جهاز مرتبط الآن. إذا مسح الطفل QR للتو، انتظر لحظة ثم افتح إدارة الأجهزة مجددًا.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.smartphone),
                      title: Text('الجهاز المرتبط ${index + 1}'),
                      subtitle: Text(device['platform'] == 'web'
                          ? 'هاتف أو متصفح ويب'
                          : 'تطبيق الهاتف'),
                      trailing: TextButton.icon(
                        onPressed: () => Navigator.pop(context, device),
                        icon: const Icon(Icons.link_off),
                        label: const Text('فصل'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
        ],
      ),
    );
    if (selected != null && mounted) {
      await _revokeDevice(dependent, selected);
    }
  }

  Future<void> _revokeDevice(
      Map<String, dynamic> dependent, Map<String, dynamic> device) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فصل جهاز الطفل؟'),
        content: Text(
            'سيتوقف جهاز ${dependent['name']} عن المزامنة، ويمكن ربطه لاحقًا برمز جديد.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('فصل الجهاز')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await _run(() async {
      await context.read<AccountController>().api.call(
          '/children/${dependent['id']}/devices/${device['id']}',
          method: 'DELETE');
      await load(selectedId);
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await work();
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _role(String value) => switch (value) {
        'OWNER' => 'مالك الأسرة',
        'GUARDIAN' => 'ولي أمر',
        'ADULT' => 'بالغ',
        'SUPPORTER' => 'داعم',
        _ => value,
      };

  @override
  Widget build(BuildContext context) {
    final family = detail?['family'] as Map?;
    final role = family?['role'] as String?;
    final canManageChildren = role == 'OWNER' || role == 'GUARDIAN';
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأسرة')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const AppNote(
                    'الأسرة مساحة خاصة. الأسماء الحقيقية تظهر لأولياء الأمر فقط، وصلاحية ولي الأمر لا تُمنح لمعلم المسجد تلقائيًا.'),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  StatusBanner(text: error!, tone: Tone.danger),
                const SectionTitle(
                  'العائلات',
                  icon: Icons.family_restroom,
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: loading ? null : _createFamily,
                    icon: const Icon(Icons.add),
                    label: const Text('أسرة جديدة'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (families.isEmpty && !loading)
                  const StatusBanner(
                    title: 'ابدأ مساحة أسرتك',
                    text: 'أنشئ أسرة ثم أضف الأطفال أو ادعُ ولي أمر آخر.',
                    tone: Tone.info,
                  )
                else if (families.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedId,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'الأسرة الحالية'),
                    items: families
                        .map((family) => DropdownMenuItem<String>(
                              value: family['id'] as String,
                              child: Text(
                                '${family['name']} — ${_role(family['role'] as String)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: loading ? null : (value) => load(value),
                  ),
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  SectionTitle(
                    family?['name'] as String? ?? 'الأسرة',
                    subtitle: 'مستواك: ${_role(role ?? '')}',
                    icon: Icons.home_outlined,
                  ),
                  if (role == 'OWNER')
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: loading ? null : _inviteMember,
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('دعوة فرد'),
                      ),
                    ),
                  _members(),
                  const SectionTitle(
                    'الأطفال والملفات التابعة',
                    subtitle: 'يربط ولي الأمر كل طفل بجهاز التدريب عند الحاجة.',
                    icon: Icons.child_care_outlined,
                  ),
                  if (canManageChildren)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        onPressed: loading ? null : _addDependent,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة طفل'),
                      ),
                    ),
                  _dependents(canManageChildren),
                  const SectionTitle(
                    'تشجيع الأسرة',
                    subtitle:
                        'هذه النقاط من ملخصات التدريب بالكاميرا، وليست حضور المسجد.',
                    icon: Icons.emoji_events_outlined,
                  ),
                  _familyLeaderboard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _members() {
    final members = (detail?['members'] as List? ?? const []);
    final canEdit = (detail?['family'] as Map?)?['role'] == 'OWNER';
    return AppCard(
      child: Column(
        children: [
          for (final raw in members)
            Builder(builder: (context) {
              final member = raw as Map;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(member['name'] as String),
                trailing: member['role'] == 'OWNER' || !canEdit
                    ? PillTag(_role(member['role'] as String))
                    : TextButton.icon(
                        onPressed: loading ? null : () => _manageMember(member),
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: Text(_role(member['role'] as String)),
                      ),
              );
            }),
        ],
      ),
    );
  }

  Widget _dependents(bool canManage) {
    final dependents = (detail?['dependents'] as List? ?? const []);
    if (dependents.isEmpty) {
      return const StatusBanner(
          text: 'لا توجد ملفات أطفال في هذه الأسرة بعد.', tone: Tone.neutral);
    }
    return Column(
      children: [
        for (final raw in dependents)
          Builder(builder: (context) {
            final child = Map<String, dynamic>.from(raw as Map);
            final devices = (child['devices'] as List? ?? const [])
                .where((raw) => (raw as Map)['revoked_at'] == null)
                .map((raw) => Map<String, dynamic>.from(raw as Map))
                .toList();
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.child_care)),
                    title: Text(child['name'] as String),
                    subtitle: Text(
                        '${child['alias'] ?? 'بلا اسم مستعار'} • ${_age(child['age_band'] as String?)}'),
                    trailing: PillTag(
                      devices.isEmpty
                          ? 'غير مرتبط بجهاز'
                          : 'مرتبط • ${devices.length}',
                      tone: devices.isEmpty ? Tone.neutral : Tone.ready,
                      icon: devices.isEmpty
                          ? Icons.phonelink_off
                          : Icons.phonelink,
                    ),
                  ),
                  if (canManage)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: loading ? null : () => _pairDevice(child),
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('ربط هاتف الطفل'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              loading ? null : () => _manageDevices(child),
                          icon: const Icon(Icons.phonelink_erase),
                          label: Text(
                              'إدارة/فصل الأجهزة${devices.isEmpty ? '' : ' (${devices.length})'}'),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _familyLeaderboard() {
    final rows = (progress?['leaderboard'] as List? ?? const []);
    if (rows.isEmpty) {
      return const StatusBanner(
          text: 'ستظهر النتائج بعد أول تدريب صالح.', tone: Tone.neutral);
    }
    return AppCard(
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++)
            Builder(builder: (context) {
              final row = rows[index] as Map;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(row['name'] as String),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${row['weekly_valid_prayers'] ?? 0} صلوات مكتملة'),
                    MovementProgress(progress: row),
                  ],
                ),
                trailing: PillTag('${row['weekly_points'] ?? 0} نقطة',
                    icon: Icons.stars_outlined, tone: Tone.ready),
              );
            }),
        ],
      ),
    );
  }

  String _age(String? value) => switch (value) {
        'CHILD_5_9' => '5–9 سنوات',
        'CHILD_10_13' => '10–13 سنة',
        'TEEN_14_17' => '14–17 سنة',
        _ => 'العمر غير محدد',
      };
}
