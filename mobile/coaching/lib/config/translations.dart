// ─────────────────────────────────────────────────────────────────────────────
// translations.dart
//
// Dictionary for UI strings in English and Arabic.
// Scalable to more screens/strings in the future without needed .arb generation.
// ─────────────────────────────────────────────────────────────────────────────

class Translations {
  static const Map<String, Map<String, String>> _dict = {
    'en': {
      'app_title': 'AI Fitness Coach',
      'pick_exercise': 'Pick an exercise',
      'load_video': 'Load Video',
      'language': 'Language',
      'english': 'English',
      'arabic': 'Arabic',
    },
    'ar': {
      'app_title': 'مدرب اللياقة الذكي',
      'pick_exercise': 'اختر تمريناً',
      'load_video': 'تحميل فيديو',
      'language': 'اللغة',
      'english': 'الإنجليزية',
      'arabic': 'العربية',
    },
  };

  /// Returns the translated string for a given key and locale code.
  /// Falls back to English if the key is missing.
  static String get(String key, String locale) {
    if (_dict.containsKey(locale) && _dict[locale]!.containsKey(key)) {
      return _dict[locale]![key]!;
    }
    // Fallback to EN
    return _dict['en']![key] ?? key;
  }
}
