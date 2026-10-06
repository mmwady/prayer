import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'english_strings.dart';

/// UI copy only. Arabic domain labels, reports, wire values and user data remain
/// unchanged; translations are resolved when a widget renders.
class AppLocalizations {
  const AppLocalizations(this.locale);
  final Locale locale;
  bool get isArabic => locale.languageCode != 'en';
  static const delegate = _AppLocalizationsDelegate();

  String text(String source, [List<Object?> arguments = const []]) {
    final translated = isArabic ? source : englishStrings[source] ?? source;
    if (arguments.isNotEmpty) {
      return translated.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
        final index = int.parse(match[1]!);
        return index < arguments.length ? '${arguments[index]}' : match[0]!;
      });
    }
    if (isArabic ||
        translated != source ||
        !RegExp(r'[\u0600-\u06ff]').hasMatch(source)) {
      return translated;
    }
    // Existing controllers emit composed Arabic notices. Match only complete,
    // catalogued messages, leaving captured errors/names/values untouched.
    for (final message in _messages) {
      final match = message.pattern.firstMatch(source);
      if (match == null) continue;
      final slots = _labelArguments[message.source] ?? const <int>{};
      final values = [
        for (var i = 1; i <= match.groupCount; i++)
          slots.contains(i - 1) ? text(match[i] ?? '') : match[i]
      ];
      return text(message.source, values);
    }
    // Lists of domain labels are translated independently, not by substring
    // replacement inside arbitrary names, notes, filenames or JSON.
    for (final separator in ['\n', '؛ ', '، ', ' / ', ' • ']) {
      if (source.contains(separator)) {
        return source
            .split(separator)
            .map((part) => text(part))
            .join(separator == '؛ '
                ? '; '
                : separator == '، '
                    ? ', '
                    : separator);
      }
    }
    return source;
  }

  static final _messages = englishStrings.keys
      .where((source) => RegExp(r'\{\d+\}').hasMatch(source))
      .map(_Message.new)
      .toList()
    ..sort((a, b) => b.literalLength.compareTo(a.literalLength));

  // Only explicitly identified domain-copy slots are translated in existing
  // composed notices. Names, notes, error details and file paths stay verbatim.
  static const _labelArguments = <String, Set<int>>{
    'الكاميرا {0} غير متاحة.': {0},
    'لم نتمكن من تأكيد {0} من الصور المتاحة.': {0},
    'ابدأ التدريب واتبع الحركة الموضحة: {0}. {1}': {0, 1},
    '{0} الحركة التالية: {1}.': {0, 1},
    'اكتمل تدريب تسلسل الحركات. {0}': {0},
    'تحميل {0}{1}': {0, 1},
    'تم تحميل {0}{1} ميجابايت': {1},
    'أوافق على المرافق {0}، ونقطة اللقاء {1}، و{2}. عند التأكيد تُتاح النقطة الدقيقة للطرفين.':
        {1, 2},
    '{0}\n{1} {2}\n{3} • {4} مقاعد\n{5}\nنطاق الانطلاق فقط سيظهر للآخرين؛ بيتك الدقيق لن يُنشر.':
        {0, 3, 5},
    'وجهة مختلفة: {0}': {0},
  };
}

class _Message {
  _Message(this.source) {
    final placeholders = RegExp(r'\{\d+\}');
    literalLength = source.replaceAll(placeholders, '').length;
    final parts = <String>[];
    var offset = 0;
    for (final match in placeholders.allMatches(source)) {
      parts.add(RegExp.escape(source.substring(offset, match.start)));
      parts.add('([\\s\\S]*?)');
      offset = match.end;
    }
    parts.add(RegExp.escape(source.substring(offset)));
    pattern = RegExp('^${parts.join()}\$');
  }
  final String source;
  late final RegExp pattern;
  late final int literalLength;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => ['ar', 'en'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

String localized(BuildContext context, String source,
        [List<Object?> arguments = const []]) =>
    (Localizations.of<AppLocalizations>(context, AppLocalizations) ??
            const AppLocalizations(Locale('ar')))
        .text(source, arguments);
