import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

typedef Json = Map<String, dynamic>;

class CompanionClient extends ChangeNotifier {
  CompanionClient({http.Client? transport})
      : _http = transport ?? http.Client();
  final http.Client _http;
  String actor = 'U01';
  String? token;
  Json? state;
  String? error;
  bool busy = false;
  bool enabled = false;
  String get base => '${Env.backendUrl}/api/v1/mosque-demo';
  Future<Json> call(String path,
      {Json? body, bool authenticated = true}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) {
      headers['Authorization'] = 'Bearer $token';
      headers['X-Demo-Actor'] = actor;
    }
    final response = await (body == null
            ? _http.get(Uri.parse('$base$path'), headers: headers)
            : _http.post(Uri.parse('$base$path'),
                headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 18));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 400) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw Exception(detail is String
          ? detail
          : 'تحقق من المدخلات أو اتصال الخادم (${response.statusCode})');
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<void> init() async {
    await run(() async {
      final config = await call('/config', authenticated: false);
      enabled = config['enabled'] == true;
      if (!enabled) {
        throw Exception(
            'وضع الديمو غير مفعّل على الخادم. راجع تعليمات التشغيل.');
      }
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('mosque_demo_token');
      actor = prefs.getString('mosque_demo_actor') ?? 'U01';
      if (token == null) {
        await newSession(prefs);
      }
      try {
        state = await call('/state');
      } catch (e) {
        // Only invalid capabilities get a replacement; network failures keep persisted state.
        if (e.toString().contains('جلسة ديمو غير صالحة')) {
          await newSession(prefs);
          state = await call('/state');
        } else {
          rethrow;
        }
      }
    });
  }

  Future<void> newSession(SharedPreferences prefs) async {
    final session = await call('/sessions', body: {}, authenticated: false);
    token = session['token'] as String;
    await prefs.setString('mosque_demo_token', token!);
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await work();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> switchActor(String value) => run(() async {
        final previousActor = actor;
        actor = value;
        try {
          state = await call('/state');
        } catch (_) {
          actor = previousActor;
          rethrow;
        }
        await (await SharedPreferences.getInstance())
            .setString('mosque_demo_actor', value);
      });
  Future<void> refresh() => run(() async {
        state = await call('/state');
      });
  Future<void> action(String action, String id, {Json extras = const {}}) =>
      run(() async {
        state = await call('/actions',
            body: {'action': action, 'id': id, ...extras});
      });
  Future<void> tool(String action, {Json extras = const {}}) => run(() async {
        state = await call('/tools', body: {'action': action, ...extras});
      });
  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
