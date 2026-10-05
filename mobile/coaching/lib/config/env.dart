// ─────────────────────────────────────────────────────────────────────────────
// env.dart
//
// Centralized runtime configuration for the Flutter app.
//
// Using `--dart-define` keeps the backend address out of source control and
// lets CI produce per-flavor builds (dev / staging / prod) without separate
// code paths. Example:
//   flutter run --dart-define=BACKEND_URL=http://192.168.1.10:8000
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Env {
  // Private constructor — this class is a namespace, not a value.
  const Env._();

  /// Mosque Companion backend. Prayer training uses local inference and storage.
  /// For an Android emulator pass
  /// BACKEND_URL=http://10.0.2.2:8000; for a device use the host LAN address.
  static const String defaultBackendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static String? _override;

  /// Hosted Web defaults to its own origin, including temporary HTTPS hosts.
  /// Explicit build configuration and saved overrides still take precedence.
  static String get backendUrl =>
      _override ??
      (kIsWeb && !const bool.hasEnvironment('BACKEND_URL')
          ? Uri.base.origin
          : defaultBackendUrl);

  static String normalizeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
          'أدخل رابط الخادم فقط، مثل https://example.com، دون مسار API.');
    }
    return uri.replace(path: '').toString();
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('backend_url');
    if (saved != null) {
      try {
        _override = normalizeUrl(saved);
      } on FormatException {
        _override = null;
      }
    }
  }

  static Future<void> save(String value) async {
    final normalized = normalizeUrl(value);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('backend_url', normalized)) {
      throw StateError('تعذر حفظ رابط الخادم.');
    }
    _override = normalized;
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove('backend_url')) {
      throw StateError('تعذر حفظ الإعداد.');
    }
    _override = null;
  }
}
