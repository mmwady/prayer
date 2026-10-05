import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'prayer_calibration.dart';
import 'prayer_reference.dart';

/// A locally imported reference is optional. No built-in illustration is ever
/// activated as measured calibration evidence, and nothing is downloaded.
class LocalPrayerReferenceRepository {
  static const storageKey = 'iqtadi.local-prayer-reference.v1';
  static const schemaVersion = 1;
  static const maximumBytes = 2 * 1024 * 1024;

  PrayerReference parse(String source) {
    if (utf8.encode(source).length > maximumBytes) {
      throw const FormatException(
          'ملف المرجع أكبر من الحد المحلي (2 ميجابايت).');
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('يجب أن يحتوي الملف على مرجع JSON واحد.');
      }
      final reference = PrayerReference.fromJson(decoded);
      PrayerCalibration(reference); // Require actual usable standing evidence.
      return reference;
    } on FormatException {
      rethrow;
    } on TypeError {
      throw const FormatException(
          'ملف المرجع ناقص أو غير متوافق مع الإصدار 2.');
    }
  }

  Future<PrayerReference?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(storageKey);
    if (stored == null) return null;
    try {
      final wrapper = jsonDecode(stored);
      if (wrapper is! Map ||
          wrapper['local_schema_version'] != schemaVersion ||
          wrapper['review_confirmed'] != true ||
          wrapper['reference'] is! Map) {
        await preferences.remove(storageKey);
        return null;
      }
      return parse(jsonEncode(wrapper['reference']));
    } on FormatException {
      await preferences.remove(storageKey);
      throw const FormatException(
          'المرجع المحفوظ غير متوافق؛ استورد نسخة محلية صالحة مجددًا.');
    }
  }

  Future<PrayerReference> save(String source,
      {required bool reviewConfirmed}) async {
    if (!reviewConfirmed) {
      throw const FormatException('أكد مراجعة المرجع قبل استخدامه للضبط.');
    }
    final reference = parse(source);
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
        storageKey,
        jsonEncode({
          'local_schema_version': schemaVersion,
          'review_confirmed': true,
          'reference': reference.toJson(),
        }));
    if (!saved) throw StateError('تعذر حفظ المرجع على هذا الجهاز.');
    return reference;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(storageKey)) {
      throw StateError('تعذر حذف المرجع من هذا الجهاز.');
    }
  }

  String export(PrayerReference reference) =>
      const JsonEncoder.withIndent('  ').convert(reference.toJson());
}
