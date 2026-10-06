import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class BrowserRecognizerScreen extends StatelessWidget {
  const BrowserRecognizerScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: Text(localized(
                context, 'التحليل المحلي بالمتصفح متاح في نسخة الويب.'))),
      );
}
