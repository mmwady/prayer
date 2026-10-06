import 'package:flutter/material.dart';

/// Locale state for the Arabic-first prayer app.
///
/// Arabic is the only supported locale, so RTL is always on. `main.dart` reads
/// [isRtl] to build the root [Directionality]; keeping it behind a
/// [ChangeNotifier] leaves room for a future locale switch without touching the
/// widget tree.
class LocaleProvider extends ChangeNotifier {
  String get localeCode => 'ar';

  bool get isRtl => true;
}
