import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';
import 'client.dart';
import 'codes.dart';
import 'platform.dart';
import 'sync_adapter.dart';

class AccountController extends ChangeNotifier {
  AccountController(
      {AccountClient? client,
      Future<String?> Function(String)? tokenReader,
      Future<void> Function(String, String?)? tokenWriter,
      String? startupPairingCode})
      : api = client ?? AccountClient(Env.backendUrl),
        _readToken = tokenReader ?? readAccountToken,
        _writeToken = tokenWriter ?? writeAccountToken,
        _startupPairingCode = startupPairingCode;
  final AccountClient api;
  final Future<String?> Function(String) _readToken;
  final Future<void> Function(String, String?) _writeToken;
  final String? _startupPairingCode;
  Map<String, dynamic>? guardian, child, childProgress;
  String? pendingInvitation;
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

  void rememberInvitation(String value) {
    pendingInvitation = value.trim();
    _emit();
  }

  void clearInvitation() {
    pendingInvitation = null;
    _emit();
  }

  Future<void> initialize() async {
    // Capture the QR fragment before Flutter's route initialization can
    // normalize the browser URL and discard an unrecognized hash.
    final pairingCode = _startupPairingCode ?? initialAccountPairingCode();
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
      _retry = Timer.periodic(
          const Duration(seconds: 30), (_) => unawaited(_heartbeat()));
    } catch (_) {
      error = 'تعذر فتح تخزين الحساب؛ التدريب المحلي متاح.';
    }
    ready = true;
    _emit();
    if (pairingCode != null) {
      await action(() => pair(pairingCode));
      clearAccountPairingLink();
    }
    unawaited(refreshSession());
  }

  Future<void> _heartbeat() async {
    if (child != null) {
      try {
        final value = await api.call('/device', child: true) as Map;
        child = {
          ...child!,
          'name': value['name'],
          'profile_kind': value['profile_kind'] ?? child!['profile_kind'],
        };
        await _saveChild();
        await refreshChildProgress();
      } on AccountError catch (e) {
        if (e.status == 401) {
          await forgetChild();
          error = 'فصل ولي الأمر هذا الجهاز.';
        }
      } catch (_) {
        // A temporary network failure must not sign the child out.
      }
    }
    await sync();
  }

  Future<void> refreshSession() async {
    if (child != null) {
      try {
        final value = await api.call('/device', child: true) as Map;
        child = {
          ...child!,
          'name': value['name'],
          'profile_kind': value['profile_kind'] ?? child!['profile_kind'],
        };
        await _saveChild();
        await refreshChildProgress();
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

  Future<void> authenticate(String email, String password,
      {String? fullName,
      String learningStage = 'GENERAL',
      String accessibilityMode = 'STANDARD'}) async {
    if (fullName != null) {
      final signupResult =
          await api.call('/auth/signup', method: 'POST', body: {
        'name': fullName.trim(),
        'email': email.trim(),
        'password': password,
        'learning_stage': learningStage,
        'accessibility_mode': accessibilityMode,
      }) as Map;
      error = signupResult['delivery'] == 'development_outbox'
          ? 'لم يُرسل بريد في وضع التطوير؛ حُفظ رابط التفعيل في صندوق البريد المحلي على الكمبيوتر.'
          : 'أرسلنا رابط تفعيل حقيقي إلى بريدك. بعد التفعيل سجّل الدخول.';
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
    final profile = session['practice_profile'];
    if (profile is Map) {
      api.deviceToken = session['practice_session_token'] as String?;
      await _writeToken(_childKey, api.deviceToken);
      child = Map<String, dynamic>.from(profile);
      await _saveChild();
      PrayerSyncAdapter.binding = binding;
      unawaited(sync());
    }
  }

  Future<void> resendVerification(String email, String password) async {
    final result = await api.call('/auth/resend',
        method: 'POST', body: {'email': email.trim()}) as Map;
    error = result['delivery'] == 'development_outbox'
        ? 'لم يُرسل بريد في وضع التطوير؛ حُفظ رابط التفعيل في صندوق البريد المحلي على الكمبيوتر.'
        : 'إذا كان البريد مسجلًا، أرسلنا إليه رابط تفعيل حقيقي.';
  }

  Future<void> recover(String email) async {
    final result = await api.call('/auth/recover',
        method: 'POST', body: {'email': email.trim()}) as Map;
    error = result['delivery'] == 'development_outbox'
        ? 'وضع محلي: حُفظ رابط الاستعادة في مجلد البريد التجريبي على الكمبيوتر؛ لم يُرسل بريد.'
        : 'إذا كان البريد مسجلًا، سيصلك رابط استعادة كلمة المرور.';
  }

  Future<void> logout() async {
    final forgetSelfProfile = child?['profile_kind'] == 'SELF';
    try {
      if (forgetSelfProfile) {
        try {
          await api.call('/device', method: 'DELETE', child: true);
        } catch (_) {
          // The server session may already be gone; local logout must continue.
        }
      }
      try {
        await api.call('/session', method: 'DELETE');
      } catch (_) {
        // Offline/revoked sessions must never trap a cached identity in the UI.
      }
    } finally {
      if (forgetSelfProfile) await forgetChild();
      await _writeToken(_guardianKey, null);
      await _prefs?.remove(_guardianKey);
      api.guardianToken = null;
      guardian = null;
      _emit();
    }
  }

  Future<void> pair(String code) async {
    if (child != null) throw StateError('Disconnect current child first');
    final value = await api.call('/pairing/redeem', method: 'POST', body: {
      'token': normalizeAccountCode(code),
      'platform': api.platform,
    }) as Map;
    api.deviceToken = value['session_token'] as String?;
    await _writeToken(_childKey, api.deviceToken);
    child = {
      for (final key in ['child_id', 'name', 'device_id']) key: value[key],
      'profile_kind': value['profile_kind'] ?? 'DEPENDENT',
    };
    await _saveChild();
    PrayerSyncAdapter.binding = binding;
    unawaited(_refreshChildProgressQuietly());
    unawaited(sync());
  }

  Future<void> refreshChildProgress() async {
    if (child == null) return;
    childProgress = Map<String, dynamic>.from(
        await api.call('/device/progress', child: true));
    _emit();
  }

  Future<void> _refreshChildProgressQuietly() async {
    try {
      await refreshChildProgress();
    } on AccountError catch (e) {
      if (e.status == 401) await forgetChild();
    } catch (_) {
      // Keep the last score visible while temporarily offline.
    }
  }

  Future<void> _saveChild() async {
    if (!await _prefs!.setString(_childKey, jsonEncode(child))) {
      throw StateError('STORAGE');
    }
  }

  Future<void> forgetChild() async {
    child = null;
    childProgress = null;
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
