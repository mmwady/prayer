import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locale state for the Arabic-first prayer app.
///
/// Presentation preference only; never changes prayer/session state.
class LocaleProvider extends ChangeNotifier {
  static const preferenceKey = 'iqtadi_locale';
  String _localeCode = 'ar';
  String get localeCode => _localeCode;
  Locale get locale => Locale(_localeCode);
  bool get isRtl => _localeCode == 'ar';

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(preferenceKey);
      if (saved == 'ar' || saved == 'en') {
        _localeCode = saved!;
        notifyListeners();
      }
    } catch (_) {/* Arabic remains the default if storage is unavailable. */}
  }

  Future<void> setLocale(String code) async {
    if ((code != 'ar' && code != 'en') || code == _localeCode) return;
    _localeCode = code;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(preferenceKey, code);
    } catch (_) {/* Switching still works without persistent storage. */}
  }
}
