import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import 'client.dart';
import 'codes.dart';
import 'controller.dart';

class MosqueAccessScreen extends StatefulWidget {
  const MosqueAccessScreen({super.key});

  @override
  State<MosqueAccessScreen> createState() => _MosqueAccessScreenState();
}

class _MosqueAccessScreenState extends State<MosqueAccessScreen> {
  Map<String, dynamic>? overview;
  List<Map<String, dynamic>> requests = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final api = context.read<AccountController>().api;
      final next = Map<String, dynamic>.from(await api.call('/overview'));
      final adminRows = next['is_platform_admin'] == true
          ? (await api.call('/admin/mosque-leader-requests') as List)
              .map((row) => Map<String, dynamic>.from(row as Map)).toList()
          : <Map<String, dynamic>>[];
      if (mounted) setState(() { overview = next; requests = adminRows; });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _request() async {
    final mosque = TextEditingController();
    final city = TextEditingController();
    final note = TextEditingController();
    var role = 'LEADER';
    final accepted = await showDialog<bool>(context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setState) => AlertDialog(
        title: const Text('طلب صلاحية قائد مسجد'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: mosque, decoration: const InputDecoration(labelText: 'اسم المسجد')),
          TextField(controller: city, decoration: const InputDecoration(labelText: 'المدينة')),
          DropdownButtonFormField<String>(initialValue: role,
            decoration: const InputDecoration(labelText: 'المهمة'),
            items: const [
              DropdownMenuItem(value: 'LEADER', child: Text('شيخ أو معلم مجموعة')),
              DropdownMenuItem(value: 'ADMIN', child: Text('مسؤول إدارة المسجد')),
            ],
            onChanged: (value) => setState(() => role = value ?? role)),
          TextField(controller: note, maxLines: 3,
            decoration: const InputDecoration(labelText: 'معلومات تساعد على التحقق')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('إرسال الطلب')),
        ],
      )));
    final mosqueName = mosque.text.trim();
    final cityName = city.text.trim();
    final noteValue = note.text.trim();
    mosque.dispose(); city.dispose(); note.dispose();
    if (accepted != true || mosqueName.length < 2 || cityName.length < 2 || !mounted) return;
    await context.read<AccountController>().action(() async {
      await context.read<AccountController>().api.call('/mosque-leader-requests', method: 'POST', body: {
        'mosque_name': mosqueName, 'city': cityName, 'requested_role': role,
        if (noteValue.isNotEmpty) 'note': noteValue,
      });
      await load();
    });
  }

  Future<void> _decide(String id, bool approve) async {
    await context.read<AccountController>().action(() async {
      await context.read<AccountController>().api.call(
        '/admin/mosque-leader-requests/$id/decision', method: 'POST', body: {'approve': approve});
      await load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final roles = overview?['mosque_roles'] as List? ?? const [];
    final ownRequests = overview?['leader_requests'] as List? ?? const [];
    final isAdmin = overview?['is_platform_admin'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('صلاحيات المسجد')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) StatusBanner(text: error!, tone: Tone.danger),
          const SectionTitle('صلاحياتي المعتمدة', icon: Icons.verified_user_outlined),
          if (roles.isEmpty) const StatusBanner(text: 'لا توجد لك صلاحية قائد مسجد حاليًا.', tone: Tone.neutral),
          for (final raw in roles) AppCard(child: ListTile(
            leading: const Icon(Icons.mosque_outlined),
            title: Text((raw as Map)['mosque_name'] as String),
            trailing: PillTag(raw['role'] == 'ADMIN' ? 'مسؤول المسجد' : 'قائد'),
          )),
          if (ownRequests.isNotEmpty) ...[
            const SectionTitle('طلباتي', icon: Icons.pending_actions_outlined),
            for (final raw in ownRequests) AppCard(child: ListTile(
              title: Text((raw as Map)['mosque_name'] as String),
              subtitle: Text(raw['city'] as String),
              trailing: PillTag(raw['status'] == 'PENDING' ? 'بانتظار التحقق' : raw['status'] as String),
            )),
          ],
          FilledButton.icon(onPressed: loading ? null : _request,
            icon: const Icon(Icons.add_moderator_outlined), label: const Text('طلب إدارة مسجد')),
          if (isAdmin) ...[
            const SectionTitle('إدارة طلبات القادة', icon: Icons.admin_panel_settings_outlined),
            if (requests.where((r) => r['status'] == 'PENDING').isEmpty)
              const StatusBanner(text: 'لا توجد طلبات معلقة.', tone: Tone.neutral),
            for (final request in requests.where((r) => r['status'] == 'PENDING'))
              AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(request['applicant_name'] as String, style: Theme.of(context).textTheme.titleMedium),
                Text('${request['mosque_name']} • ${request['city']}'),
                Text(request['applicant_email'] as String),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => _decide(request['id'] as String, false), child: const Text('رفض'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: () => _decide(request['id'] as String, true), child: const Text('اعتماد'))),
                ]),
              ])),
          ],
        ]),
      )),
    );
  }
}

class MosqueGroupsScreen extends StatefulWidget {
  const MosqueGroupsScreen({super.key});

  @override
  State<MosqueGroupsScreen> createState() => _MosqueGroupsScreenState();
}

class _MosqueGroupsScreenState extends State<MosqueGroupsScreen> {
  List<Map<String, dynamic>> groups = [];
  List<Map<String, dynamic>> memberships = [];
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> mosques = [];
  Map<String, dynamic>? dashboard;
  Map<String, dynamic>? mosqueBoard;
  String? selectedId;
  String? error;
  bool loading = true;
  bool leaderMode = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load([String? groupId]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<AccountController>().api;
      final groupRows = (await api.call('/mosque-groups') as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final overview = Map<String, dynamic>.from(await api.call('/overview'));
      final membershipRows = (overview['joined_groups'] as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final mosqueRows = (await api.call('/mosques') as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final personalIds = membershipRows.map((row) => row['group_id']).toSet();
      final visibleRows = leaderMode
          ? groupRows.where((row) => row['access'] == 'LEADER').toList()
          : groupRows.where((row) => personalIds.contains(row['id'])).toList();
      final nextId = groupId ??
          selectedId ??
          (visibleRows.isEmpty ? null : visibleRows.first['id'] as String);
      Map<String, dynamic>? nextDashboard;
      Map<String, dynamic>? nextBoard;
      List<Map<String, dynamic>> nextMessages = [];
      if (nextId != null) {
        nextDashboard = Map<String, dynamic>.from(
            await api.call('/mosque-groups/$nextId/dashboard'));
        final mosqueId = (nextDashboard['group'] as Map)['mosque_id'] as String;
        nextBoard = Map<String, dynamic>.from(
            await api.call('/mosques/$mosqueId/leaderboard'));
        final group = nextDashboard['group'] as Map;
        if (!leaderMode && group['age_band'] == 'ADULT') {
          nextMessages = (await api.call('/mosque-groups/$nextId/messages') as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
        }
      }
      if (!mounted) return;
      setState(() {
        groups = visibleRows;
        memberships = membershipRows;
        messages = nextMessages;
        mosques = mosqueRows;
        selectedId = nextId;
        dashboard = nextDashboard;
        mosqueBoard = nextBoard;
      });
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _message(Object exception) => exception is AccountError
      ? exception.toString()
      : 'تعذر تحميل مجموعات المسجد. حاول مجددًا.';

  Future<void> _join() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => const MosqueJoinScreen(target: 'SELF')));
    if (mounted) await load();
  }

  Future<void> _joinChild() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const MosqueJoinScreen(target: 'CHILD')));
    if (mounted) await load();
  }

  Future<void> _leave(Map membership) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مغادرة المجموعة؟'),
        content: Text(
            'سيغادر ${membership['alias']} هذه المجموعة، ويمكن الانضمام لاحقًا بدعوة جديدة.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('مغادرة')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await context.read<AccountController>().api.call(
          '/mosque-groups/${membership['group_id']}/members/${membership['profile_id']}',
          method: 'DELETE');
      selectedId = null;
      await load();
    });
  }

  Future<void> _approve(String profileId) async {
    if (selectedId == null) return;
    await _run(() async {
      await context.read<AccountController>().api.call(
          '/mosque-groups/$selectedId/members/$profileId/approve',
          method: 'POST');
      await load(selectedId);
    });
  }

  Future<void> _composeMessage({Map<String, dynamic>? replyTo}) async {
    if (selectedId == null) return;
    final text = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(replyTo == null ? 'رسالة إلى المجموعة' : 'رد على ${replyTo['author_alias']}'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 280,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'مثال: أنا في الطريق إلى المسجد، من سينضم إليّ؟',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('إرسال')),
        ],
      ),
    );
    final value = text.text.trim();
    text.dispose();
    if (accepted != true || value.isEmpty || !mounted) return;
    await _run(() async {
      await context.read<AccountController>().api.call(
        '/mosque-groups/$selectedId/messages', method: 'POST', body: {
          'body': value,
          if (replyTo != null) 'parent_id': replyTo['id'],
        });
      await load(selectedId);
    });
  }

  Future<void> _reject(String profileId) async {
    if (selectedId == null) return;
    await _run(() async {
      await context.read<AccountController>().api.call(
          '/mosque-groups/$selectedId/members/$profileId',
          method: 'DELETE');
      await load(selectedId);
    });
  }

  Future<void> _createGroup() async {
    final staffed = mosques
        .where(
            (mosque) => mosque['role'] == 'ADMIN' || mosque['role'] == 'LEADER')
        .toList();
    if (staffed.isEmpty) return;
    var mosqueId = staffed.first['id'] as String;
    var ageBand = 'CHILD_5_9';
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إنشاء مجموعة مسجد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: mosqueId,
                  decoration: const InputDecoration(labelText: 'المسجد'),
                  items: staffed
                      .map((mosque) => DropdownMenuItem<String>(
                          value: mosque['id'] as String,
                          child: Text(mosque['name'] as String)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => mosqueId = value ?? mosqueId),
                ),
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'اسم المجموعة'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: ageBand,
                  decoration: const InputDecoration(labelText: 'الفئة'),
                  items: const [
                    DropdownMenuItem(
                        value: 'CHILD_5_9', child: Text('5–9 سنوات')),
                    DropdownMenuItem(
                        value: 'CHILD_10_13', child: Text('10–13 سنة')),
                    DropdownMenuItem(
                        value: 'TEEN_14_17', child: Text('14–17 سنة')),
                    DropdownMenuItem(value: 'ADULT', child: Text('بالغون')),
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
                child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    final value = name.text.trim();
    name.dispose();
    if (accepted != true || value.isEmpty || !mounted) return;
    await _run(() async {
      final result = await context
          .read<AccountController>()
          .api
          .call('/mosques/$mosqueId/groups', method: 'POST', body: {
        'name': value,
        'age_band': ageBand,
        'timezone': 'Asia/Riyadh',
      }) as Map;
      await load(result['id'] as String);
    });
  }

  Future<void> _inviteFamilies() async {
    if (selectedId == null) return;
    await _run(() async {
      final invite = Map<String, dynamic>.from(
          await context.read<AccountController>().api.call(
                '/mosque-groups/$selectedId/invite',
                method: 'POST',
              ));
      if (mounted) {
        await _showQr(
          'دعوة الانضمام إلى المجموعة',
          invite,
          'يمسح الشخص الرمز للانضمام بنفسه، أو يمسحه ولي الأمر من خيار ضم طفل. طلب الطفل يحتاج قبول قائد المسجد.',
        );
      }
    });
  }

  Future<void> _createAttendance() async {
    if (selectedId == null) return;
    var prayer = 'fajr';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('فتح حضور الصلاة'),
          content: DropdownButtonFormField<String>(
            initialValue: prayer,
            decoration: const InputDecoration(labelText: 'الصلاة'),
            items: const [
              DropdownMenuItem(value: 'fajr', child: Text('الفجر')),
              DropdownMenuItem(value: 'dhuhr', child: Text('الظهر')),
              DropdownMenuItem(value: 'asr', child: Text('العصر')),
              DropdownMenuItem(value: 'maghrib', child: Text('المغرب')),
              DropdownMenuItem(value: 'isha', child: Text('العشاء')),
            ],
            onChanged: (value) =>
                setDialogState(() => prayer = value ?? prayer),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('فتح لمدة 30 دقيقة')),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    final now = DateTime.now();
    final day =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _run(() async {
      final session = Map<String, dynamic>.from(
          await context.read<AccountController>().api.call(
        '/mosque-groups/$selectedId/attendance-sessions',
        method: 'POST',
        body: {'prayer': prayer, 'prayer_day': day, 'valid_minutes': 30},
      ));
      if (mounted) {
        await _showQr(
          'رمز حضور ${_prayer(prayer)}',
          session,
          'هذا الرمز للحضور فقط، ولا يضيف أي نقاط إلى تقييم التدريب بالكاميرا.',
        );
      }
      await load(selectedId);
    });
  }

  Future<void> _markAttendance(String sessionId, String profileId) async {
    await _run(() async {
      await context.read<AccountController>().api.call(
        '/attendance-sessions/$sessionId/mark',
        method: 'POST',
        body: {'profile_id': profileId},
      );
      await load(selectedId);
    });
  }

  Future<void> _showQr(String title, Map<String, dynamic> value, String note) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(data: value['qr_payload'] as String, size: 220),
                const SizedBox(height: 12),
                SelectableText(value['code'] as String,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(note, textAlign: TextAlign.center),
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

  @override
  Widget build(BuildContext context) {
    final isLeader = leaderMode;
    final staffed = mosques.any(
        (mosque) => mosque['role'] == 'ADMIN' || mosque['role'] == 'LEADER');
    return Scaffold(
      appBar: AppBar(title: const Text('مجموعات المسجد')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (staffed)
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.person_outline),
                          label: Text('وضعي الشخصي')),
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.admin_panel_settings_outlined),
                          label: Text('وضع قائد المسجد')),
                    ],
                    selected: {leaderMode},
                    onSelectionChanged: loading
                        ? null
                        : (value) {
                            setState(() {
                              leaderMode = value.first;
                              selectedId = null;
                              dashboard = null;
                            });
                            load();
                          },
                  ),
                const AppNote(
                    'الانضمام للأطفال يتم بموافقة ولي الأمر. تعرض المجموعة أسماء مستعارة فقط، ويظل الحضور منفصلًا عن تقييم التدريب.'),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  StatusBanner(text: error!, tone: Tone.danger),
                if (leaderMode)
                  const StatusBanner(
                    title: 'لوحة قائد المسجد',
                    text:
                        'يمكنك إنشاء المجموعات، إصدار QR لأولياء الأمور، وفتح حضور الصلاة. صلاحية القائد منفصلة عن وصاية الأسرة.',
                    tone: Tone.ready,
                  ),
                SectionTitle(
                  leaderMode ? 'المجموعات التي أديرها' : 'عضوياتي في المسجد',
                  icon: Icons.groups_outlined,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!leaderMode) ...[
                      OutlinedButton.icon(
                        onPressed: loading ? null : _join,
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('انضم بنفسي'),
                      ),
                      OutlinedButton.icon(
                        onPressed: loading ? null : _joinChild,
                        icon: const Icon(Icons.child_care),
                        label: const Text('ضم طفل بموافقتي'),
                      ),
                    ],
                    if (leaderMode)
                      FilledButton.icon(
                        onPressed: loading ? null : _createGroup,
                        icon: const Icon(Icons.add),
                        label: const Text('مجموعة جديدة'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (!leaderMode) _membershipCards(),
                if (groups.isEmpty && !loading)
                  const StatusBanner(
                    title: 'لا توجد مجموعات بعد',
                    text:
                        'استخدم دعوة المسجد للانضمام، أو أنشئ مجموعة إن كنت قائدًا معتمدًا.',
                    tone: Tone.info,
                  )
                else if (groups.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedId,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'المجموعة الحالية'),
                    items: groups
                        .map((group) => DropdownMenuItem<String>(
                              value: group['id'] as String,
                              child: Text(
                                '${group['mosque_name']} — ${group['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: loading ? null : (value) => load(value),
                  ),
                if (dashboard != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _groupHeader(isLeader),
                  if (isLeader) _pendingMembers(),
                  if (!isLeader &&
                      (dashboard!['group'] as Map)['age_band'] == 'ADULT')
                    _adultConversation(),
                  const SectionTitle(
                    'لوحة الحضور',
                    subtitle: 'حضور المسجد — مستقل عن نقاط التدريب بالكاميرا.',
                    icon: Icons.how_to_reg_outlined,
                  ),
                  _attendanceBoard(isLeader),
                  const SectionTitle(
                    'لوحة التدريب',
                    subtitle:
                        'ملخصات التدريب بالكاميرا فقط — لا صور ولا فيديو.',
                    icon: Icons.self_improvement,
                  ),
                  _practiceBoard(),
                  const SectionTitle(
                    'منافسة مجموعات المسجد',
                    subtitle: 'إجماليات المجموعات فقط؛ لا تظهر أسماء الأطفال.',
                    icon: Icons.emoji_events_outlined,
                  ),
                  _mosqueLeaderboard(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _membershipCards() {
    if (memberships.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        children: [
          for (final membership in memberships)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(membership['join_kind'] == 'CHILD'
                  ? Icons.child_care
                  : Icons.person_outline),
              title: Text('${membership['mosque_name']} — ${membership['group_name']}'),
              subtitle: Text(membership['status'] == 'PENDING'
                  ? '${membership['alias']} • بانتظار قبول قائد المسجد'
                  : '${membership['alias']} • عضوية نشطة'),
              trailing: TextButton(
                onPressed: loading ? null : () => _leave(membership),
                child: const Text('مغادرة'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _adultConversation() {
    final roots = messages.where((message) => message['parent_id'] == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'مجلس المجموعة',
          subtitle: 'رسائل تشجيعية قصيرة لأعضاء مجموعة البالغين فقط.',
          icon: Icons.forum_outlined,
          trailing: IconButton(
            tooltip: 'تحديث الرسائل',
            onPressed: loading ? null : () => load(selectedId),
            icon: const Icon(Icons.refresh),
          ),
        ),
        FilledButton.icon(
          onPressed: loading ? null : () => _composeMessage(),
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('إرسال رسالة للمجموعة'),
        ),
        const SizedBox(height: 8),
        if (roots.isEmpty)
          const StatusBanner(
            text: 'لا توجد رسائل بعد. ابدأ برسالة تشجيع للذهاب إلى المسجد.',
            tone: Tone.neutral,
          ),
        for (final message in roots)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(message['author_alias'] as String),
                  subtitle: Text(message['body'] as String),
                  trailing: IconButton(
                    tooltip: 'رد',
                    onPressed: loading ? null : () => _composeMessage(replyTo: message),
                    icon: const Icon(Icons.reply),
                  ),
                ),
                for (final reply in messages.where(
                    (candidate) => candidate['parent_id'] == message['id']))
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 28),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.subdirectory_arrow_left),
                      title: Text(reply['author_alias'] as String),
                      subtitle: Text(reply['body'] as String),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pendingMembers() {
    final rows = dashboard?['pending_members'] as List? ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('طلبات انضمام الأطفال',
            subtitle: 'وافق على الطلب بعد تحقق المسجد من ولي الأمر.',
            icon: Icons.approval_outlined),
        AppCard(
          child: Column(
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                Builder(builder: (context) {
                  final row = rows[index] as Map;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.child_care_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(row['alias'] as String,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const Text(
                                      'طلب موثق بموافقة ولي الأمر • بانتظار القرار'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: loading
                                    ? null
                                    : () => _reject(
                                        row['profile_id'] as String),
                                icon: const Icon(Icons.close),
                                label: const Text('رفض الطلب'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: loading
                                    ? null
                                    : () => _approve(
                                        row['profile_id'] as String),
                                icon: const Icon(Icons.check),
                                label: const Text('قبول الطفل'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                if (index != rows.length - 1) const Divider(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupHeader(bool isLeader) {
    final group = dashboard!['group'] as Map;
    return AppCard(
      tone: Tone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(group['name'] as String,
              style: Theme.of(context).textTheme.titleLarge),
          Text('${group['mosque_name']} • ${group['city']}'),
          const SizedBox(height: 8),
          Text(dashboard!['privacy'] as String,
              style: Theme.of(context).textTheme.bodySmall),
          if (isLeader) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: loading ? null : _inviteFamilies,
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('عرض QR للانضمام'),
                ),
                OutlinedButton.icon(
                  onPressed: loading ? null : _createAttendance,
                  icon: const Icon(Icons.how_to_reg),
                  label: const Text('فتح حضور صلاة'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _attendanceBoard(bool isLeader) {
    final rows = dashboard!['attendance_leaderboard'] as List? ?? const [];
    final sessions = dashboard!['attendance_sessions'] as List? ?? const [];
    final active = sessions.isEmpty ? null : sessions.last as Map;
    if (rows.isEmpty) {
      return const StatusBanner(
          text: 'لا توجد بيانات حضور مشاركة بعد.', tone: Tone.neutral);
    }
    return AppCard(
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++)
            Builder(builder: (context) {
              final row = rows[index] as Map;
              final attendance = row['attendance'] as Map;
              final percent = ((attendance['rate'] as num) * 100).round();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(row['alias'] as String),
                subtitle: Text(
                    '${attendance['attended']} من ${attendance['eligible']} • $percent%'),
                trailing:
                    isLeader && active != null && active['closed_at'] == null
                        ? IconButton.filledTonal(
                            tooltip: 'تسجيل حاضر',
                            onPressed: loading
                                ? null
                                : () => _markAttendance(active['id'] as String,
                                    row['profile_id'] as String),
                            icon: const Icon(Icons.check),
                          )
                        : null,
              );
            }),
        ],
      ),
    );
  }

  Widget _practiceBoard() {
    final rows = dashboard!['practice_leaderboard'] as List? ?? const [];
    if (rows.isEmpty) {
      return const StatusBanner(
          text: 'لا توجد نتائج تدريب مشاركة بعد.', tone: Tone.neutral);
    }
    return AppCard(
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++)
            Builder(builder: (context) {
              final row = rows[index] as Map;
              final practice = row['practice'] as Map;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(row['alias'] as String),
                subtitle:
                    Text('${practice['weekly_valid_prayers']} صلوات مكتملة'),
                trailing: PillTag('${practice['weekly_points']} نقطة',
                    tone: Tone.ready, icon: Icons.stars_outlined),
              );
            }),
        ],
      ),
    );
  }

  Widget _mosqueLeaderboard() {
    final rows = mosqueBoard?['groups'] as List? ?? const [];
    if (rows.isEmpty) {
      return const StatusBanner(
          text: 'لا توجد إجماليات للمسجد بعد.', tone: Tone.neutral);
    }
    return AppCard(
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++)
            Builder(builder: (context) {
              final row = rows[index] as Map;
              final percent = ((row['attendance_rate'] as num) * 100).round();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(row['group_name'] as String),
                subtitle: Text('${row['member_count']} أعضاء'),
                trailing: PillTag('$percent% حضور', tone: Tone.info),
              );
            }),
        ],
      ),
    );
  }

  String _prayer(String value) => switch (value) {
        'fajr' => 'الفجر',
        'dhuhr' => 'الظهر',
        'asr' => 'العصر',
        'maghrib' => 'المغرب',
        'isha' => 'العشاء',
        _ => value,
      };
}

class MosqueJoinScreen extends StatefulWidget {
  const MosqueJoinScreen(
      {super.key, this.initialToken, this.target = 'SELF'});

  final String? initialToken;
  final String target;

  @override
  State<MosqueJoinScreen> createState() => _MosqueJoinScreenState();
}

class _MosqueJoinScreenState extends State<MosqueJoinScreen> {
  late final TextEditingController token;
  final alias = TextEditingController();
  List<Map<String, dynamic>> profiles = [];
  String? profileId;
  String? error;
  bool loading = true;
  bool sharePractice = true;
  bool shareAttendance = true;
  bool leaderboard = true;

  @override
  void initState() {
    super.initState();
    token = TextEditingController(text: widget.initialToken ?? '');
    Future.microtask(_loadProfiles);
  }

  @override
  void dispose() {
    token.dispose();
    alias.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    try {
      final api = context.read<AccountController>().api;
      final overview = Map<String, dynamic>.from(await api.call('/overview'));
      final self = overview['practice_profile'] as Map;
      final choices = <Map<String, dynamic>>[
        if (widget.target == 'SELF') {
          'id': self['id'],
          'name': self['name'],
          'description': 'ملفي الشخصي',
        }
      ];
      if (widget.target == 'CHILD') {
        for (final raw in overview['families'] as List? ?? const []) {
          final family = raw as Map;
          if (family['role'] != 'OWNER' && family['role'] != 'GUARDIAN') {
            continue;
          }
          final details = Map<String, dynamic>.from(
              await api.call('/families/${family['id']}'));
          for (final childRaw in details['dependents'] as List? ?? const []) {
            final child = childRaw as Map;
            choices.add({
              'id': child['id'],
              'name': child['name'],
              'description': 'طفل في ${family['name']}',
              'alias': child['alias'],
            });
          }
        }
      }
      if (!mounted) return;
      setState(() {
        profiles = choices;
        profileId = choices.isEmpty ? null : choices.first['id'] as String;
        alias.text = choices.isEmpty ? '' : choices.first['name'] as String;
      });
    } catch (exception) {
      if (mounted) {
        setState(() => error = exception is AccountError
            ? exception.toString()
            : 'تعذر تحميل ملفات الأسرة.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _selectProfile(String? value) {
    if (value == null) return;
    final selected = profiles.firstWhere((profile) => profile['id'] == value);
    setState(() {
      profileId = value;
      alias.text = (selected['alias'] ?? selected['name']) as String;
    });
  }

  Future<void> _join() async {
    final code = token.text.trim();
    final displayName = alias.text.trim();
    if (code.isEmpty || displayName.length < 2 || profileId == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final controller = context.read<AccountController>();
      final result = await controller.api.call('/mosque-groups/join', method: 'POST', body: {
        'token': code,
        'profile_id': profileId,
        'alias': displayName,
        'share_practice': sharePractice,
        'share_attendance': shareAttendance,
        'leaderboard': leaderboard,
      }) as Map;
      controller.clearInvitation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['status'] == 'PENDING'
                ? 'أُرسل طلب الطفل إلى قائد المسجد للموافقة.'
                : 'تم انضمامك إلى المجموعة.')));
        Navigator.pop(context, true);
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = exception is AccountError
            ? exception.toString()
            : 'تعذر إكمال الانضمام. حاول مجددًا.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.target == 'CHILD'
            ? 'ضم طفل إلى مجموعة مسجد'
            : 'الانضمام بنفسي إلى مجموعة مسجد')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                StatusBanner(
                  title: widget.target == 'CHILD'
                      ? 'موافقة ولي الأمر ثم قبول المسجد'
                      : 'عضوية شخصية مستقلة',
                  text: widget.target == 'CHILD'
                      ? 'اختر طفلك ووافق على البيانات المختصرة. قائد المسجد يقبل الطلب، لكنه لا يصبح ولي أمر.'
                      : 'هذا الانضمام يخصك أنت، سواء كنت مسلمًا جديدًا أو كبير سن أو عضوًا عاديًا، ولا يرتبط بالأطفال.',
                  tone: Tone.info,
                ),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  StatusBanner(text: error!, tone: Tone.danger),
                TextField(
                  controller: token,
                  textDirection: TextDirection.ltr,
                  decoration:
                      const InputDecoration(labelText: 'رمز دعوة المجموعة'),
                ),
                OutlinedButton.icon(
                  onPressed: loading
                      ? null
                      : () async {
                          final value = await Navigator.of(context)
                              .push<String>(MaterialPageRoute(
                                  builder: (_) => const GroupInviteScanner()));
                          if (value != null && mounted) token.text = value;
                        },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('مسح QR دعوة المسجد'),
                ),
                if (profiles.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: profileId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'من سينضم؟'),
                    items: profiles
                        .map((profile) => DropdownMenuItem<String>(
                              value: profile['id'] as String,
                              child: Text(
                                '${profile['name']} — ${profile['description']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: loading ? null : _selectProfile,
                  ),
                if (!loading && profiles.isEmpty)
                  const StatusBanner(
                    title: 'لا يوجد طفل مسجل',
                    text: 'أضف الطفل أولًا من إدارة الأسرة، ثم ارجع لمسح دعوة المجموعة.',
                    tone: Tone.info,
                  ),
                TextField(
                  controller: alias,
                  decoration: const InputDecoration(
                      labelText: 'الاسم المستعار الظاهر للمجموعة'),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('الموافقة',
                          style: Theme.of(context).textTheme.titleMedium),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('مشاركة ملخص التدريب'),
                        subtitle: const Text(
                            'النقاط والصلوات المكتملة فقط؛ لا صور أو فيديو.'),
                        value: sharePractice,
                        onChanged: loading
                            ? null
                            : (value) => setState(() => sharePractice = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('مشاركة حضور المسجد'),
                        subtitle:
                            const Text('سجل مستقل لا يغير تقييم التدريب.'),
                        value: shareAttendance,
                        onChanged: loading
                            ? null
                            : (value) =>
                                setState(() => shareAttendance = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('الظهور في لوحة التشجيع'),
                        subtitle: const Text('بالاسم المستعار فقط.'),
                        value: leaderboard,
                        onChanged: loading
                            ? null
                            : (value) => setState(() => leaderboard = value),
                      ),
                      const AppNote(
                          'لن نشارك الاسم الحقيقي أو البريد أو الموقع أو أي وسائط من الكاميرا.'),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: loading || profileId == null ? null : _join,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(widget.target == 'CHILD'
                      ? 'أوافق وأرسل طلب الطفل'
                      : 'أوافق وأنضم بنفسي'),
                ),
              ],
            ),
          ),
        ),
      );
}

class GroupInviteScanner extends StatefulWidget {
  const GroupInviteScanner({super.key});

  @override
  State<GroupInviteScanner> createState() => _GroupInviteScannerState();
}

class _GroupInviteScannerState extends State<GroupInviteScanner> {
  final scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool found = false;

  @override
  void dispose() {
    unawaited(scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('مسح دعوة مجموعة المسجد')),
        body: Column(
          children: [
            const AppNote(
                'امسح QR الذي يعرضه قائد المسجد، ثم اختر الطفل وراجع الموافقة.'),
            Expanded(
              child: MobileScanner(
                controller: scanner,
                errorBuilder: (context, error) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text('تعذر فتح الكاميرا. أدخل رمز الدعوة يدويًا.'),
                  ),
                ),
                onDetect: (capture) {
                  if (found) return;
                  for (final barcode in capture.barcodes) {
                    final value = normalizeAccountCode(barcode.rawValue ?? '');
                    if (value.startsWith('iqtadi-group:')) {
                      found = true;
                      Navigator.pop(context, value);
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
