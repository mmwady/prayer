import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';
import '../ui/backend_settings_drawer.dart';
import 'client.dart';
import 'demo_map.dart';
import 'location.dart';

class MosqueCompanionScreen extends StatefulWidget {
  const MosqueCompanionScreen({super.key, this.client});
  final CompanionClient? client;
  @override
  State<MosqueCompanionScreen> createState() => _MosqueCompanionScreenState();
}

class _MosqueCompanionScreenState extends State<MosqueCompanionScreen> {
  late final CompanionClient client;
  String page = 'home';
  bool publishing = false;
  int step = 0;
  String mosque = 'quba',
      mode = 'walk',
      language = 'ar',
      gender = 'any',
      meeting = 'public',
      beneficiary = 'U01';
  bool support = false, back = false, adult = true, basic = true;
  Json? origin;
  Json? publicMeeting;
  String prayer = 'الجمعة';
  Set<String> availableLanguages = {'ar', 'en'};
  List<Json> places = [], matches = [], excluded = [];
  String? requestId, locationMessage;
  final lat = TextEditingController(), lng = TextEditingController();
  final departure = TextEditingController(text: '11:50'),
      date = TextEditingController(text: '2026-10-02');
  final returnTime = TextEditingController(text: '13:00'),
      passengers = TextEditingController(text: '1');
  final detour = TextEditingController(text: '8'),
      note = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    client = widget.client ?? CompanionClient();
    client.addListener(changed);
    if (client.state == null) {
      client.init();
    }
  }

  void changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    client.removeListener(changed);
    if (widget.client == null) {
      client.dispose();
    }
    for (final c in [
      lat,
      lng,
      departure,
      date,
      returnTime,
      passengers,
      detour,
      note
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Json get state => client.state ?? {};
  Json get me => Map<String, dynamic>.from(state['me'] ?? {});
  List<Json> list(String key) => ((state[key] ?? []) as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  Json get destination => list('places').firstWhere((p) => p['id'] == mosque);
  String clock(String value) => value.length >= 16
      ? '${value.substring(0, 10)} • ${value.substring(11, 16)}'
      : value;
  String mosqueName(String id) =>
      list('places').firstWhere((p) => p['id'] == id)['name'] as String;
  String languageNames(List values) => values
      .map(
          (v) => {'ar': 'العربية', 'en': 'الإنجليزية', 'ur': 'الأردية'}[v] ?? v)
      .join(' / ');
  void start(bool offer) {
    publishing = offer;
    step = 0;
    page = 'form';
    beneficiary = client.actor == 'U04' ? 'U03' : client.actor;
    publicMeeting = null;
    availableLanguages = Set<String>.from(me['languages'] as List);
    mosque = ['U03', 'U04', 'U05', 'U09'].contains(client.actor)
        ? 'qiblatain'
        : 'quba';
    mode =
        ['U03', 'U04', 'U05', 'U06', 'U07', 'U08', 'U09'].contains(client.actor)
            ? 'car'
            : 'walk';
    support = ['U03', 'U04', 'U05'].contains(client.actor);
    back = support;
    language = ['U07', 'U08'].contains(client.actor) ? 'ur' : 'ar';
    gender = client.actor == 'U10' ? 'female' : 'any';
    departure.text = mosque == 'qiblatain'
        ? '11:55'
        : mode == 'car'
            ? '12:00'
            : '11:50';
    date.text = (state['now'] as String).substring(0, 10);
    passengers.text = offer ? '2' : '1';
    meeting = mode == 'car' ? 'home' : 'public';
    origin = Map<String, dynamic>.from(me['origin'] as Map);
    lat.text = '${origin!['lat']}';
    lng.text = '${origin!['lng']}';
    locationMessage = null;
    note.clear();
    setState(() {});
  }

  Widget button(String text, VoidCallback? action,
          {IconData? icon, bool secondary = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: SizedBox(
              width: double.infinity,
              child: secondary
                  ? OutlinedButton(
                      onPressed: client.busy ? null : action,
                      child: Text(localized(context, text),
                          textAlign: TextAlign.center))
                  : FilledButton.icon(
                      onPressed: client.busy ? null : action,
                      icon: Icon(icon ?? Icons.arrow_back),
                      label: Text(localized(context, text),
                          textAlign: TextAlign.center))));
  Widget card(List<Widget> children) => AppCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  Widget title(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(localized(context, text),
          style: Theme.of(context).textTheme.titleLarge));
  Widget dropdown(String label, String value, Map<String, String> items,
          void Function(String) change) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: DropdownButtonFormField<String>(
              key: ValueKey('$label-$value'),
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: localized(context, label)),
              items: items.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(localized(context, e.value),
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged:
                  client.busy ? null : (v) => setState(() => change(v!))));
  Widget field(String label, TextEditingController controller,
          {bool number = false, String? Function(String?)? validate}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextFormField(
              controller: controller,
              keyboardType: number
                  ? const TextInputType.numberWithOptions(
                      decimal: true, signed: true)
                  : TextInputType.text,
              decoration: InputDecoration(labelText: localized(context, label)),
              textDirection: number ? TextDirection.ltr : null,
              validator: validate == null
                  ? null
                  : (value) {
                      final error = validate(value);
                      return error == null ? null : localized(context, error);
                    }));
  String? requiredNumber(String? value) =>
      int.tryParse(value ?? '') == null ? 'أدخل عددًا صحيحًا' : null;
  Widget check(String label, bool value, void Function(bool) change) =>
      CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(localized(context, label)),
          value: value,
          onChanged: client.busy ? null : (v) => setState(() => change(v!)));
  Future<bool> confirmDialog(String text) async =>
      await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text(localized(context, 'راجع وأكد')),
                  content: SingleChildScrollView(
                      child: Text(localized(context, text))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text(localized(context, 'رجوع'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(localized(context, 'أوافق')))
                  ])) ??
      false;
  Json journey() {
    final time = departure.text.trim();
    final dt = DateTime.tryParse('${date.text.trim()}T$time:00+03:00');
    if (dt == null ||
        !RegExp(r'^\d{2}:\d{2}$').hasMatch(time) ||
        int.parse(time.split(':')[0]) > 23 ||
        int.parse(time.split(':')[1]) > 59 ||
        DateTime.tryParse(date.text.trim())
                ?.toIso8601String()
                .substring(0, 10) !=
            date.text.trim()) {
      throw Exception('أدخل تاريخًا صحيحًا ووقتًا بصيغة 11:50');
    }
    return {
      'origin': origin,
      'mosque': mosque,
      'departure': '${date.text.trim()}T$time:00+03:00',
      'mode': mode,
      'support': support,
      'prayer': prayer
    };
  }

  Future<void> preview() async {
    await client.run(() async {
      final response = await client.call('/preview', body: journey());
      places = (response['places'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
    });
  }

  Future<void> candidates(String id) async {
    await client.run(() async {
      final result = await client.call('/requests/$id/matches');
      matches = (result['matches'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      requestId = id;
      excluded = ((result['excluded'] ?? []) as List)
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
      page = 'matches';
    });
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) {
      return;
    }
    if (publishing) {
      final agreed = await confirmDialog(
          '${mosqueName(mosque)}\n${date.text} ${departure.text}\n${mode == 'walk' ? 'مشي' : 'سيارة'} • ${passengers.text} مقاعد\n${back ? 'عودة ${returnTime.text}' : 'ذهاب فقط'}\nنطاق الانطلاق فقط سيظهر للآخرين؛ بيتك الدقيق لن يُنشر.');
      if (!agreed) {
        return;
      }
    }
    await client.run(() async {
      final payload = journey();
      if (publishing) {
        payload.addAll({
          'seats': int.parse(passengers.text),
          'languages': availableLanguages.toList(),
          'max_detour': int.parse(detour.text),
          'return_enabled': back,
          'return_at': back ? '${date.text}T${returnTime.text}:00+03:00' : null
        });
        final response = await client.call('/trips', body: payload);
        client.state = Map<String, dynamic>.from(response['state']);
        page = 'home';
      } else {
        payload.addAll({
          'beneficiary': beneficiary,
          'language': language,
          'gender': gender,
          'passengers': int.parse(passengers.text),
          'return_required': back,
          'desired_return_at':
              back ? '${date.text}T${returnTime.text}:00+03:00' : null,
          'meeting': meeting,
          'public_meeting': publicMeeting,
          'note': note.text,
          'adult_confirmed': adult,
          'basic_support_only': basic
        });
        final response = await client.call('/requests', body: payload);
        client.state = Map<String, dynamic>.from(response['state']);
        requestId = response['id'];
        page = 'trip';
        final result = await client.call('/requests/$requestId/matches');
        matches = (result['matches'] as List)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        excluded = ((result['excluded'] ?? []) as List)
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        page = 'matches';
      }
    });
  }

  Future<void> cancel(String id, {bool trip = false}) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(localized(context, 'سبب الإلغاء')),
                content: TextField(
                    controller: reason,
                    maxLength: 160,
                    decoration: InputDecoration(
                        hintText: localized(context, 'اكتب سبب الإلغاء'))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(localized(context, 'رجوع'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, reason.text.trim()),
                      child: Text(localized(context, 'إلغاء الرحلة')))
                ]));
    // Keep the controller alive until the dialog's dismissal animation finishes.
    if (value != null && value.isNotEmpty) {
      await client.action(trip ? 'cancel_trip' : 'cancel', id,
          extras: {'reason': value});
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        drawer: const BackendSettingsDrawer(),
        appBar: AppBar(
            title: Text(localized(context, 'رفيق المسجد')),
            leading: IconButton(
                tooltip: localized(context, 'رجوع'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (page == 'home') {
                    Navigator.pop(context);
                  } else {
                    setState(() => page = 'home');
                  }
                }),
            actions: [
              Builder(
                  builder: (context) => IconButton(
                      tooltip: localized(context, 'إعدادات رفيق المسجد'),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.settings_outlined))),
              IconButton(
                  tooltip: localized(context, 'تحديث الحالة'),
                  onPressed: client.busy ? null : client.refresh,
                  icon: const Icon(Icons.refresh))
            ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                    key: ValueKey('$page-$step-${client.actor}'),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      AppNote(
                          localized(context,
                              'بيانات تجريبية • حسابات ومنازل خيالية • لا إشعارات لأشخاص حقيقيين'),
                          icon: Icons.science_outlined),
                      if (client.busy) const LinearProgressIndicator(),
                      if (client.error != null)
                        card([
                          Text(localized(context, client.error!),
                              style: const TextStyle(color: AppColors.danger)),
                          button(
                              'إعادة المحاولة',
                              client.state == null
                                  ? client.init
                                  : client.refresh,
                              secondary: true)
                        ]),
                      if (client.state == null && !client.busy)
                        Text(localized(context,
                            'فعّل MOSQUE_DEMO_ENABLED=true على الخادم ثم أعد المحاولة. التشغيل الحقيقي غير متاح بعد.')),
                      if (client.state != null) ...[
                        dropdown('الشخصية التجريبية', client.actor, {
                          for (final p in list('personas'))
                            p['id'] as String: '${p['id']} ${p['name']}'
                        }, (v) {
                          page = 'home';
                          client.switchActor(v);
                        }),
                        Text(
                            localized(
                                context,
                                'الجمعة التجريبية • {0} • الرياض\nكل المواعيد مواعيد رحلات تجريبية وليست إقامة فعلية.',
                                [clock(state['now'])]),
                            style: Theme.of(context).textTheme.bodySmall),
                        if (page == 'home') ...home(),
                        if (page == 'form') ...wizard(),
                        if (page == 'matches') ...matchCards(),
                        if (page == 'inbox') ...inbox(),
                        if (page == 'trip') ...tripCards(),
                      ],
                    ]))),
      ));
  List<Widget> home() => [
        title('إلى المسجد، برفقة مناسبة'),
        Text(localized(context,
            'اختر انطلاقك ووجهتك، ثم اتفقا على اللقاء والعودة قبل تأكيد الرحلة.')),
        button('أحتاج رفيقًا', () => start(false), icon: Icons.people_outline),
        button('سأذهب ويمكنني المساعدة', () => start(true),
            icon: Icons.volunteer_activism_outlined, secondary: true),
        button('طلبات المرافقة', () => setState(() => page = 'inbox'),
            icon: Icons.inbox_outlined, secondary: true),
        button('رحلتي', () => setState(() => page = 'trip'),
            icon: Icons.route, secondary: true),
        for (final r in list('requests').where((r) => r['mine'] == true))
          card([
            Text(localized(context, '{0} • {1}',
                [r['name'], localized(context, mosqueName(r['mosque']))])),
            Text(localized(context, '{0} • {1}', [
              localized(context, r['status_label']),
              clock(r['departure'])
            ])),
            if (['draft', 'no_match', 'rejected', 'expired']
                .contains(r['status']))
              button('راجع الخيارات أو ابحث مجددًا', () => candidates(r['id']),
                  secondary: true),
            if (!['cancelled', 'completed'].contains(r['status']))
              button('فتح الرحلة', () => setState(() => page = 'trip'),
                  secondary: true),
          ]),
        title('رحلاتي المنشورة'),
        for (final t
            in list('trips').where((t) => t['provider'] == client.actor))
          card([
            Text(localized(context, '{0} • {1}', [
              localized(context, mosqueName(t['mosque'])),
              clock(t['departure'])
            ])),
            Text(localized(context, '{0} مقاعد متبقية • {1}',
                [t['remaining'], tripStatus(t['display_status'])])),
            Text(localized(
                context,
                t['return_enabled'] == true
                    ? 'عودة ${clock(t['return_at'])}'
                    : 'ذهاب فقط')),
            if (!['cancelled', 'completed'].contains(t['status']))
              button('إلغاء الرحلة المنشورة', () => cancel(t['id'], trip: true),
                  secondary: true),
          ]),
        if (list('notifications').isNotEmpty) ...[
          title('تحديثاتك داخل الديمو'),
          for (final n in list('notifications').reversed.take(4))
            AppNote(localized(context, n['text']),
                icon: Icons.notifications_none)
        ],
        ExpansionTile(
            title: Text(localized(context, 'أدوات عرض اللجنة — ديمو فقط')),
            children: [
              button('S03 • بدء سيناريو أحمد ويوسف', () => scenario('U01'),
                  secondary: true),
              button('S04 • بدء سيناريو عمر ومحمود', () => scenario('U04'),
                  secondary: true),
              button('S06 • مريم وسارة', () => scenario('U10'),
                  secondary: true),
              button('تقدم الساعة 6 دقائق', () => client.tool('advance'),
                  secondary: true),
              button(
                  state['route_failure'] == true
                      ? 'استعادة عرض المسار'
                      : 'محاكاة تعطل خدمة الخرائط',
                  () => client.tool('route_failure',
                      extras: {'enabled': state['route_failure'] != true}),
                  secondary: true),
              button('إعادة ضبط جميع بيانات هذه الجلسة', () async {
                if (await confirmDialog(
                    'سيتم حذف طلبات وحجوزات جلسة الديمو وإعادة الساعة إلى 11:30.')) {
                  await client.tool('reset');
                }
              }, secondary: true),
              AppNote(localized(context,
                  'تبديل الشخصية يحافظ على الطلبات. الديمو يستخدم Backend وSQLite؛ ليس نظام حسابات إنتاجيًا.')),
            ]),
      ];
  String tripStatus(String s) =>
      {
        'available': 'متاحة',
        'full': 'ممتلئة',
        'ongoing': 'جارية',
        'completed': 'مكتملة',
        'cancelled': 'ملغاة',
        'closed': 'مغلقة'
      }[s] ??
      s;
  Future<void> scenario(String actor) async {
    await client.switchActor(actor);
    if (client.error == null) {
      start(false);
    }
  }

  List<Widget> wizard() => [
        title(['من أين ستخرج؟', 'اختر المسجد', 'تفاصيل الرحلة'][step]),
        Text(localized(context, 'الخطوة {0} من 3 • {1}', [
          step + 1,
          localized(context, publishing ? 'نشر رحلة' : 'طلب مرافقة')
        ])),
        if (step == 0) ...originFields(),
        if (step == 1) ...mosqueFields(),
        if (step == 2)
          Form(
              key: form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: details())),
        if (step > 0)
          button('الخطوة السابقة', () => setState(() => step--),
              secondary: true),
      ];
  List<Widget> originFields() => [
        if (!publishing && client.actor == 'U04')
          AppNote(localized(context,
              'أنت عمر؛ تنشئ طلب الحاج محمود بعلاقة أسرية مخولة تجريبيًا.')),
        button('موقعي الحالي — اطلب إذن GPS', () async {
          if (!await confirmDialog(
              'سيطلب الجهاز إذن الموقع لتحديد الانطلاق فقط. لن يُحفظ كبيت تلقائيًا. في الديمو يمكنك استخدام نقطة خيالية بالمدينة.')) {
            return;
          }
          await client.run(() async {
            try {
              final p = await DeviceLocation().current();
              origin = {...p, 'label': 'موقعي الحالي', 'approximate': true};
              lat.text = '${p['lat']}';
              lng.text = '${p['lng']}';
              locationMessage =
                  'دقة GPS: ${(p['accuracy'] as num).round()} متر${(p['accuracy'] as num) > 100 ? ' — دقة ضعيفة، عدّل النقطة' : ''}';
            } catch (e) {
              locationMessage =
                  'تعذر GPS أو رُفض الإذن. يمكنك إدخال النقطة أو اختيارها أدناه.';
            }
          });
        }, icon: Icons.my_location),
        button('استخدم منزلًا تجريبيًا — محاكاة الانطلاق', () {
          origin = Map<String, dynamic>.from(me['origin']);
          lat.text = '${origin!['lat']}';
          lng.text = '${origin!['lng']}';
          setState(
              () => locationMessage = 'محاكاة • منزل خيالي في المدينة المنورة');
        }, secondary: true),
        if (me['home'] != null)
          button('بيتي المحفوظ', () {
            origin = Map<String, dynamic>.from(me['home']);
            lat.text = '${origin!['lat']}';
            lng.text = '${origin!['lng']}';
            setState(() {});
          }, secondary: true),
        if (locationMessage != null)
          AppNote(localized(context, locationMessage!),
              icon: Icons.location_on_outlined),
        field('خط العرض — إدخال يدوي', lat, number: true),
        field('خط الطول — إدخال يدوي', lng, number: true),
        DemoMap(
            points: [if (origin != null) origin!, ...list('places')],
            onPoint: (a, b) {
              origin = {
                'lat': a,
                'lng': b,
                'label': 'نقطة يدوية مقترحة — تحتاج تأكيدًا',
                'approximate': true
              };
              lat.text = a.toStringAsFixed(6);
              lng.text = b.toStringAsFixed(6);
              setState(() {});
            }),
        Text(localized(context,
            'اضغط على الخريطة لتعديل الانطلاق. النقاط المقترحة غير متحقق من مداخلها أو صلاحية التقاط السيارات.')),
        button('احفظ هذا المكان كبيتي', () async {
          if (!readOrigin()) {
            return;
          }
          if (await confirmDialog(
              'هل توافق صراحة على حفظ هذه النقطة كبيتك لهذا الحساب التجريبي؟')) {
            await client.run(() async {
              client.state =
                  await client.call('/home?consent=true', body: origin);
            });
          }
        }, secondary: true),
        button('التالي: اختيار المسجد', () async {
          if (!readOrigin()) {
            return;
          }
          await preview();
          if (client.error == null) {
            setState(() => step = 1);
          }
        }),
      ];
  bool readOrigin() {
    final a = double.tryParse(lat.text), b = double.tryParse(lng.text);
    if (a == null ||
        b == null ||
        !a.isFinite ||
        !b.isFinite ||
        a.abs() > 90 ||
        b.abs() > 180) {
      client.error = 'أدخل إحداثيات صحيحة';
      setState(() {});
      return false;
    }
    origin = {
      'lat': a,
      'lng': b,
      'label': origin?['label'] ?? 'نقطة يدوية',
      'approximate': true
    };
    return true;
  }

  List<Widget> mosqueFields() {
    final p = places.firstWhere((p) => p['id'] == mosque);
    return [
      dropdown('وسيلة الانتقال', mode, {'walk': 'مشي', 'car': 'سيارة'}, (v) {
        mode = v;
        preview();
      }),
      DemoMap(
          points: [
            {...origin!, 'label': 'البداية'},
            {...p, 'label': p['name']},
            {
              ...Map<String, dynamic>.from(p['meeting']),
              'label': 'اللقاء المقترح'
            }
          ],
          path: ((p['route']['path'] ?? []) as List)
              .map((v) => Map<String, dynamic>.from(v))
              .toList(),
          onPoint: (a, b) {
            final nearest = places.reduce((x, y) =>
                ((x['lat'] - a) * (x['lat'] - a) +
                            (x['lng'] - b) * (x['lng'] - b)) <
                        ((y['lat'] - a) * (y['lat'] - a) +
                            (y['lng'] - b) * (y['lng'] - b))
                    ? x
                    : y);
            setState(() => mosque = nearest['id']);
          }),
      for (final place in places)
        card([
          ListTile(
              leading: Icon(place['id'] == mosque
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              onTap: () => setState(() {
                    mosque = place['id'];
                    publicMeeting = null;
                  }),
              title: Text(place['name']),
              subtitle: Text(localized(
                  context, 'مسافة مباشرة: {0} متر — ليست طول الطريق\n{1}', [
                place['direct_meters'],
                localized(
                    context,
                    place['route']['minutes'] == null
                        ? 'تعذر التوجيه'
                        : 'زمن محاكى ${place['route']['minutes']} دقيقة')
              ]))),
        ]),
      AppNote(localized(context, p['route']['label']), icon: Icons.route),
      AppNote(localized(context,
          'مركز المسجد مستقل عن نقطة اللقاء. المدخل ونقطة النزول غير متحقق منهما؛ قد يلزم مشي بعد النزول. مقصد قباء نطاق تقريبي، وليس تصريح التقاط سيارات.')),
      button('التالي: تفاصيل الرحلة', () => setState(() => step = 2)),
    ];
  }

  List<Widget> details() => [
        Text(localized(context, '{0} • {1}', [
          localized(context, mosqueName(mosque)),
          localized(context, mode == 'walk' ? 'مشي' : 'سيارة')
        ])),
        AppNote(localized(
            context, 'مواعيد رحلات تجريبية، وليست مواعيد صلاة أو إقامة.')),
        dropdown(
            'الصلاة',
            prayer,
            {
              for (final p in [
                'الجمعة',
                'الفجر',
                'الظهر',
                'العصر',
                'المغرب',
                'العشاء'
              ])
                p: p
            },
            (v) => prayer = v),
        field('التاريخ YYYY-MM-DD — الرياض', date),
        field('موعد الخروج HH:mm', departure),
        if (mode == 'car')
          check('توصيلة مع دعم بسيط أثناء المشي', support, (v) => support = v),
        if (!publishing)
          dropdown(
              publishing ? 'لغة متاحة' : 'اللغة المفضلة',
              language,
              {'ar': 'العربية', 'en': 'الإنجليزية', 'ur': 'الأردية'},
              (v) => language = v),
        if (publishing) ...[
          Text(localized(context, 'اللغات المتاحة')),
          for (final entry
              in {'ar': 'العربية', 'en': 'الإنجليزية', 'ur': 'الأردية'}.entries)
            check(entry.value, availableLanguages.contains(entry.key), (v) {
              if (v) {
                availableLanguages.add(entry.key);
              } else {
                availableLanguages.remove(entry.key);
              }
            }),
        ],
        if (!publishing)
          dropdown(
              'تفضيل المرافق',
              gender,
              {'any': 'بلا تفضيل', 'male': 'رجل', 'female': 'امرأة'},
              (v) => gender = v),
        field(publishing ? 'المقاعد المتاحة' : 'عدد الركاب', passengers,
            number: true, validate: requiredNumber),
        check(publishing ? 'ألتزم بتوفير العودة' : 'أحتاج رحلة عودة', back,
            (v) => back = v),
        if (back) field('موعد العودة التقريبي HH:mm', returnTime),
        if (!publishing) ...[
          dropdown(
              'نقطة اللقاء',
              meeting,
              {
                'home': 'المنزل — لا يُكشف قبل التأكيد',
                'public': 'نقطة عامة مقترحة قرب الوجهة'
              },
              (v) => meeting = v),
          if (meeting == 'public') ...[
            Text(localized(context,
                'اختر نقطة لقاء عامة بالضغط على الخريطة؛ تحتاج تأكيد إتاحتها.')),
            DemoMap(
                points: [
                  {...origin!, 'label': 'الانطلاق'},
                  {...destination, 'label': destination['name']},
                  {
                    ...(publicMeeting ??
                        Map<String, dynamic>.from(destination['meeting'])),
                    'label': 'اللقاء المقترح'
                  }
                ],
                onPoint: (a, b) => setState(() => publicMeeting = {
                      'lat': a,
                      'lng': b,
                      'label': 'نقطة لقاء عامة مقترحة — تحتاج تأكيدًا',
                      'approximate': true
                    })),
          ],
          field('ملاحظة قصيرة عن المساعدة المطلوبة', note),
          AppNote(localized(context,
              'لا توجد خدمة AI متصلة هنا. راجع نوع الدعم واللغة بنفسك؛ الملاحظة لا تغيّر شروط الأهلية.')),
          check('المستفيد بالغ؛ لا طلب للأطفال', adult, (v) => adult = v),
          check('الطلب دعم بسيط؛ لا نقل طبي أو متخصص', basic, (v) => basic = v),
        ],
        if (publishing)
          field('أقصى انحراف مقبول بالدقائق', detour,
              number: true, validate: requiredNumber),
        AppNote(localized(context,
            'للبلوغ والدعم البسيط فقط. اعتماد الديمو ليس تحققًا إنتاجيًا.')),
        button(publishing ? 'راجع الملخص ثم انشر' : 'اعرض الرفقاء المناسبين',
            submit,
            icon: Icons.search),
      ];
  List<Widget> matchCards() => [
        title('رفقاء ورحلات مناسبة'),
        AppNote(localized(context,
            'مطابقة حسب المسار والتفضيلات • كل دقائق الطرق واللقاء محاكاة معلّمة، دون AI')),
        if (matches.isEmpty) ...[
          card([
            Text(localized(context,
                'لا يوجد مرافق مناسب لهذه الوجهة والتوقيت والاحتياج. لم نختَر بديلًا لا يغطي طلبك.')),
            button('إنشاء طلب انتظار / البحث عن مؤهلين', () async {
              await client.action('search', requestId!);
              if (client.error == null) {
                setState(() => page = 'trip');
              }
            }, secondary: true),
            button('إلغاء الطلب وتعديل الموعد أو الاحتياج', () async {
              await client.action('cancel', requestId!,
                  extras: {'reason': 'تعديل الطلب'});
              if (client.error == null) {
                start(false);
              }
            }, secondary: true)
          ]),
        ],
        for (final m in matches)
          card([
            Row(children: [
              CircleAvatar(child: Text((m['name'] as String).substring(0, 1))),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(m['name'],
                      style: Theme.of(context).textTheme.titleLarge))
            ]),
            Text(localized(
                context,
                m['verification'] == 'demo-approved'
                    ? 'اعتماد مساعدة تجريبي محفوظ'
                    : 'حساب تجريبي • لا اعتماد مساعدة متخصص')),
            Text(localized(context, '{0} • {1}', [
              localized(
                  context,
                  m['mode'] == 'walk'
                      ? 'رفيق مشي'
                      : m['support'] == true
                          ? 'توصيلة ودعم بسيط'
                          : 'توصيلة'),
              localized(context, languageNames(m['languages'] as List))
            ])),
            Text(localized(context, '{0} • الخروج {1}', [
              localized(context, mosqueName(m['mosque'])),
              clock(m['departure'])
            ])),
            Text(localized(context, 'اللقاء: {0}\nموعد محاكى: {1}', [
              localized(context, m['meeting_label']),
              clock(m['meeting_at'])
            ])),
            Text(localized(context, '{0} مقاعد متبقية • انحراف محاكى {1} دقيقة',
                [m['seats'], m['detour']])),
            Text(localized(
                context,
                m['return_enabled'] == true
                    ? 'عودة ملتزم بها ${clock(m['return_at'])}'
                    : 'ذهاب فقط')),
            Text(localized(context, 'سبب الترشيح: {0}',
                [localized(context, (m['reasons'] as List).join('، '))])),
            button('طلب الانضمام', () async {
              await client
                  .action('join', requestId!, extras: {'trip': m['trip']});
              if (client.error == null) {
                setState(() => page = 'trip');
              }
            }),
          ]),
        if (matches.isNotEmpty)
          button('ابحث عن مرافق — أرسل دعوات محدودة', () async {
            await client.action('search', requestId!);
            if (client.error == null) {
              setState(() => page = 'trip');
            }
          }, secondary: true),
        if (excluded.isNotEmpty)
          ExpansionTile(
              title: Text(localized(context, 'لماذا استُبعدت خيارات أخرى؟')),
              children: [
                for (final option in excluded)
                  ListTile(
                      title: Text(option['name']),
                      subtitle: Text(localized(
                          context, (option['reasons'] as List).join('، ')))),
              ]),
      ];
  List<Widget> inbox() => [
        title('طلبات المرافقة'),
        AppNote(localized(context,
            'قبل تأكيد الطرفين يُعرض نطاق الانطلاق فقط. القبول يحجز مؤقتًا؛ الدعوة وحدها لا تحجز مقعدًا.')),
        if (list('invitations').isEmpty)
          Text(localized(context, 'لا توجد دعوات لهذا الحساب حاليًا.')),
        for (final i in list('invitations')) ...invitation(i),
      ];
  List<Widget> invitation(Json i) {
    final r = list('requests').firstWhere((r) => r['id'] == i['request']);
    return [
      card([
        Text(localized(context, '{0} • {1}',
            [r['name'], localized(context, mosqueName(r['mosque']))])),
        Text(localized(context, '{0}\n{1}',
            [localized(context, r['area']), clock(r['departure'])])),
        Text(localized(context, '{0} • {1} ركاب • {2}', [
          localized(
              context,
              r['support'] == true
                  ? 'توصيلة ودعم بسيط'
                  : r['mode'] == 'walk'
                      ? 'مشي'
                      : 'توصيلة'),
          r['passengers'],
          localized(context,
              r['return_required'] == true ? 'العودة مطلوبة' : 'ذهاب فقط')
        ])),
        Text(localized(context, 'حالة الدعوة: {0} • المهلة {1}',
            [inviteStatus(i['status']), clock(i['expires'])])),
        if (i['status'] == 'pending') ...[
          button(
              r['return_required'] == true
                  ? 'قبول والتزام صريح بالعودة'
                  : 'قبول وتقديم عرض', () async {
            if (await confirmDialog(
                '${r['return_required'] == true ? 'أوافق على الذهاب والعودة والدعم المطلوب.' : 'أوافق على المرافقة.'}\nينتظر العرض تأكيد طالب المساعدة، ويُحجز المقعد 5 دقائق تجريبية.')) {
              await client.action('accept', i['id'],
                  extras: {'return_commit': r['return_required'] == true});
            }
          }, icon: Icons.check),
          button('رفض', () => client.action('reject', i['id']),
              secondary: true),
        ],
      ])
    ];
  }

  String inviteStatus(String s) =>
      {
        'pending': 'بانتظار ردك',
        'accepted': 'قُدم عرض',
        'rejected': 'مرفوضة',
        'expired': 'انتهت المهلة',
        'closed': 'مغلقة'
      }[s] ??
      s;
  List<Widget> tripCards() => [
        title('رحلتي'),
        if (list('requests').isEmpty)
          Text(localized(context, 'لا توجد رحلة؛ ابدأ بطلب رفيق أو نشر رحلة.')),
        for (final r in list('requests')) ...trip(r),
      ];
  List<Widget> trip(Json r) {
    final offer = r['offer'] as Map?;
    final stages = [
      'confirmed',
      'departed',
      'meeting',
      'started',
      'arrived',
      if (r['return_required'] == true) 'return_started',
      'completed'
    ];
    final labels = {
      'confirmed': 'تم تأكيد الطرفين',
      'departed': 'خرجت',
      'meeting': 'وصلت نقطة اللقاء',
      'started': 'بدأنا الرحلة',
      'arrived': 'وصلنا للمسجد',
      'return_started': 'بدأنا العودة',
      'completed':
          r['return_required'] == true ? 'وصلنا وانتهت العودة' : 'إنهاء الذهاب'
    };
    final stage = offer?['stage'] as String?;
    final active = offer?['status'] == 'confirmed';
    final index = stage == null ? -1 : stages.indexOf(stage);
    return [
      card([
        Text(
            localized(context, '{0} • {1}',
                [r['name'], localized(context, mosqueName(r['mosque']))]),
            style: Theme.of(context).textTheme.titleLarge),
        Text(localized(context, '{0} • {1}',
            [localized(context, r['status_label']), clock(r['departure'])])),
        Text(localized(
            context,
            r['return_required'] == true
                ? 'الذهاب والعودة التزامان مستقلان'
                : 'رحلة ذهاب فقط')),
        if (offer != null) ...[
          Text(localized(context, 'المرافق: {0}', [offer['name']])),
          Text(localized(context, 'اللقاء المتوقع (محاكى): {0}',
              [clock(offer['meeting_at'])])),
          if (r['status'] == 'offered')
            Text(localized(
                context, 'الحجز مؤقت حتى {0}', [clock(offer['expires'])])),
          if (r['status'] == 'offered' && r['mine'] == true)
            button('أؤكد العرض ونقطة اللقاء', () async {
              if (await confirmDialog(
                  'أوافق على المرافق ${offer['name']}، ونقطة اللقاء ${r['meeting'] == 'home' ? 'المنزل' : 'النقطة العامة المقترحة'}، و${r['return_required'] == true ? 'الذهاب والعودة' : 'الذهاب فقط'}. عند التأكيد تُتاح النقطة الدقيقة للطرفين.')) {
                await client.action('confirm', r['id']);
              }
            }, icon: Icons.check_circle_outline),
          if (active || r['status'] == 'completed') ...[
            Text(localized(context, 'الحالة: {0}',
                [localized(context, labels[stage].toString())])),
            if (r['return_required'] == true)
              Text(localized(
                  context,
                  stage == 'completed'
                      ? 'العودة مكتملة'
                      : 'العودة ما زالت ملتزمًا بها • ${clock(offer['return_at'])}')),
            if (r['meeting_point'] != null) ...[
              Text(localized(context, 'اللقاء: {0}',
                  [localized(context, r['meeting_point']['label'])])),
              DemoMap(
                  points: [
                    {
                      ...Map<String, dynamic>.from(r['origin']),
                      'label': 'الانطلاق'
                    },
                    {...destinationFor(r), 'label': mosqueName(r['mosque'])},
                    {
                      ...Map<String, dynamic>.from(r['meeting_point']),
                      'label': 'اللقاء'
                    },
                  ],
                  path: ((r['route']['path'] ?? []) as List)
                      .map((p) => Map<String, dynamic>.from(p))
                      .toList()),
              button('افتح الخرائط لنقطة اللقاء',
                  () => navigation(r['meeting_point']),
                  secondary: true),
              button('افتح الخرائط لوجهة المسجد',
                  () => navigation(destinationFor(r)),
                  secondary: true),
              AppNote(localized(context,
                  'الخرائط الخارجية تحسب الطريق الفعلي إن توفر. نقطة اللقاء مقترحة؛ اتفقا على إتاحتها، ومركز المسجد ليس مدخل سيارات.')),
            ],
            if (active && index >= 0 && index < stages.length - 1)
              button(
                  labels[stages[index + 1]]!,
                  () => client.action('progress', r['id'],
                      extras: {'stage': stages[index + 1]}),
                  icon: Icons.directions_walk),
            if (stage == 'arrived' && r['return_required'] == true)
              AppNote(localized(context,
                  'وصلتم للمسجد؛ الطلب لم يكتمل لأن العودة لم تُنجز.')),
          ],
        ],
        if (r['status'] == 'searching')
          AppNote(localized(context,
              'بانتظار المرافق. بدّل إلى الشخصية المدعوة، وافتح طلبات المرافقة. بعد قبولها ارجع وأكد العرض.')),
        if (['draft', 'expired', 'rejected', 'no_match']
                .contains(r['status']) &&
            r['mine'] == true)
          button('البحث عن خيار تالٍ', () => candidates(r['id']),
              secondary: true),
        if (r['cancel_reason'] != null)
          Text(localized(context, 'سبب الإلغاء: {0}', [r['cancel_reason']])),
        if (!['completed', 'cancelled'].contains(r['status']) &&
            (r['mine'] == true || offer?['provider'] == client.actor))
          button('إلغاء مع السبب', () => cancel(r['id']), secondary: true),
      ])
    ];
  }

  Json destinationFor(Json r) =>
      list('places').firstWhere((p) => p['id'] == r['mosque']);
  Future<void> navigation(dynamic p) => client.run(() async {
        await navigateTo(
            (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
      });
}
