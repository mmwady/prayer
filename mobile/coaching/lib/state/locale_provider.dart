import 'package:flutter/material.dart';

import '../config/translations.dart';

class LocaleProvider extends ChangeNotifier {
  String _localeCode = 'en';

  String get localeCode => _localeCode;

  bool get isRtl => _localeCode == 'ar';

  void setLocale(String code) {
    if (code == _localeCode) return;
    _localeCode = code;
    notifyListeners();
  }

  /// Helper to get a string using the active locale.
  String t(String key) {
    return Translations.get(key, _localeCode);
  }
}
