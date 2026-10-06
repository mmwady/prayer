import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';
import 'client.dart';
import 'platform.dart';
import 'sync_adapter.dart';

class AccountController extends ChangeNotifier {
  AccountController(
      {AccountClient? client,
      Future<String?> Function(String)? tokenReader,
      Future<void> Function(String, String?)? tokenWriter})
      : api = client ?? AccountClient(Env.backendUrl),
        _readToken = tokenReader ?? readAccountToken,
        _writeToken = tokenWriter ?? writeAccountToken;
  final AccountClient api;
  final Future<String?> Function(String) _readToken;
  final Future<void> Function(String, String?) _writeToken;
  Map<String, dynamic>? guardian, child;
  List<Map<String, dynamic>> queue = [];
  String? error;
  bool ready = false, syncing = false, busy = false;
  SharedPreferences? _prefs;
  Timer? _retry;
  Future<void> _mutation = Future.value();
  bool _disposed = false;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  String get _scope => Uri.encodeComponent(api.base);
  String get _childKey => 'account_child_$_scope';
  String get _guardianKey => 'account_guardian_$_scope';
  String get _queueKey => 'account_queue_$_scope';
  String? get binding => child == null ? null : '$_scope|${child!['child_id']}';

  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final cached = _prefs!.getString(_childKey);
      if (cached != null) child = Map<String, dynamic>.from(jsonDecode(cached));
      final parent = _prefs!.getString(_guardianKey);
      if (parent != null) {
        guardian = Map<String, dynamic>.from(jsonDecode(parent));
      }
      final pending = _prefs!.getString(_queueKey);
      if (pending != null) {
        queue = (jsonDecode(pending) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      api.guardianToken = await _readToken(_guardianKey);
      api.deviceToken = await _readToken(_childKey);
      PrayerSyncAdapter.binding = binding;
      PrayerSyncAdapter.sink = enqueue;
      _retry =
          Timer.periodic(const Duration(seconds: 30), (_) => unawaited(sync()));
    } catch (_) {
      error = 'تعذر فتح تخزين الحساب؛ التدريب المحلي متاح.';
    }
    ready = true;
    _emit();
    unawaited(refreshSession());
  }

  Future<void> refreshSession() async {
    if (child != null) {
      try {
        final value = await api.call('/device', child: true) as Map;
        child = {...child!, 'name': value['name']};
        await _saveChild();
      } on AccountError catch (e) {
        if (e.status == 401) {
          await forgetChild();
          error = e.toString();
        }
      } catch (_) {/* Cached identity and queue survive offline startup. */}
    }
    if (guardian != null) {
      try {
        guardian = Map<String, dynamic>.from(await api.call('/me'));
      } on AccountError catch (e) {
        if (e.status == 401) {
          guardian = null;
          await _prefs?.remove(_guardianKey);
        }
      } catch (_) {/* Show cached identity; dashboard reports offline. */}
    }
    _emit();
    await sync();
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    busy = true;
    error = null;
    _emit();
    try {
      await work();
    } catch (e) {
      error = e is AccountError
          ? e.toString()
          : 'تعذر الاتصال أو حفظ البيانات؛ حاول مجددًا.';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> authenticate(String email, String password, String role,
      {String? fullName}) async {
    if (fullName != null) {
      await api.call('/auth/signup', method: 'POST', body: {
        'name': fullName.trim(),
        'email': email.trim(),
        'password': password,
        'role': role
      });
      error = 'أرسلنا رابط تفعيل البريد. بعد التفعيل سجّل الدخول.';
      return;
    }
    final session = await api.call('/session',
        method: 'POST',
        body: {'email': email.trim(), 'password': password}) as Map;
    api.guardianToken = session['session_token'] as String?;
    await _writeToken(_guardianKey, api.guardianToken);
    guardian = Map<String, dynamic>.from(session['guardian']);
    if (!await _prefs!.setString(_guardianKey, jsonEncode(guardian))) {
      throw StateError('STORAGE');
    }
  }

  Future<void> resendVerification(String email, String password) async {
    await api
        .call('/auth/resend', method: 'POST', body: {'email': email.trim()});
    error = 'أرسلنا رابط التفعيل إلى بريدك.';
  }

  Future<void> recover(String email) async {
    await api
        .call('/auth/recover', method: 'POST', body: {'email': email.trim()});
    error = 'إذا كان البريد مسجلًا، سيصلك رابط استعادة كلمة المرور.';
  }

  Future<void> logout() async {
    await api.call('/session', method: 'DELETE');
    await _writeToken(_guardianKey, null);
    await _prefs?.remove(_guardianKey);
    api.guardianToken = null;
    guardian = null;
  }

  Future<void> pair(String code) async {
    if (child != null) throw StateError('Disconnect current child first');
    final value = await api.call('/pairing/redeem',
        method: 'POST',
        body: {'token': code.trim(), 'platform': api.platform}) as Map;
    api.deviceToken = value['session_token'] as String?;
    await _writeToken(_childKey, api.deviceToken);
    child = {
      for (final key in ['child_id', 'name', 'device_id']) key: value[key]
    };
    await _saveChild();
    PrayerSyncAdapter.binding = binding;
    unawaited(sync());
  }

  Future<void> _saveChild() async {
    if (!await _prefs!.setString(_childKey, jsonEncode(child))) {
      throw StateError('STORAGE');
    }
  }

  Future<void> forgetChild() async {
    child = null;
    api.deviceToken = null;
    PrayerSyncAdapter.binding = null;
    await _writeToken(_childKey, null);
    await _prefs?.remove(_childKey);
    _emit();
  }

  Future<void> disconnect() async {
    await api.call('/device', method: 'DELETE', child: true);
    await forgetChild();
  }

  Future<void> _serialized(Future<void> Function() work) {
    final next = _mutation.then((_) => work());
    _mutation = next.catchError((Object _) {});
    return next;
  }

  Future<void> _saveQueue() async {
    if (!await _prefs!.setString(_queueKey, jsonEncode(queue))) {
      throw StateError('QUEUE_STORAGE_FAILED');
    }
  }

  Future<void> enqueue(String owner, Map<String, dynamic> result) async {
    // A strict allowlist is the only object serialized to the account backend.
    const allowed = {
      'client_attempt_id',
      'prayer',
      'performed_at',
      'valid',
      'sequence_valid',
      'uncertain',
      'confidence',
      'rakats_expected',
      'rakats_completed',
      'analysis_version',
      'movements_detected',
      'movements_expected',
      'movement_score'
    };
    final payload = {
      for (final e in result.entries)
        if (allowed.contains(e.key)) e.key: e.value
    };
    if (payload.values
        .any((v) => v != null && v is! String && v is! num && v is! bool)) {
      throw const FormatException(
          'Only scalar prayer summaries may synchronize');
    }
    if (payload['prayer'] == 'demo' || owner != binding) return;
    await _serialized(() async {
      if (queue.any((e) =>
          e['binding'] == owner &&
          e['payload']['client_attempt_id'] == payload['client_attempt_id'])) {
        return;
      }
      queue.add({'binding': owner, 'payload': payload});
      try {
        await _saveQueue();
      } catch (_) {
        error = 'تعذر حفظ النتيجة للمزامنة. التقرير المحلي متاح.';
        _emit();
        rethrow;
      }
    });
    _emit();
    unawaited(sync());
  }

  Future<void> sync() async {
    if (syncing || child == null || _prefs == null) return;
    syncing = true;
    _emit();
    try {
      for (final entry in List<Map<String, dynamic>>.from(queue)) {
        final owner = binding;
        if (entry['binding'] != owner) continue;
        await api.call('/attempts',
            method: 'POST',
            child: true,
            body: Map<String, dynamic>.from(entry['payload']));
        await _serialized(() async {
          queue.remove(entry);
          try {
            await _saveQueue();
          } catch (_) {
            queue.add(entry);
            rethrow;
          }
        });
      }
      error = null;
    } on AccountError catch (e) {
      error = e.toString();
      if (e.status == 401) await forgetChild();
    } catch (_) {
      error = 'النتائج محفوظة على الجهاز؛ ستُزامن عند عودة الاتصال.';
    } finally {
      syncing = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    api.close();
    PrayerSyncAdapter.sink = null;
    PrayerSyncAdapter.binding = null;
    super.dispose();
  }
}
