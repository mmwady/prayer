// ─────────────────────────────────────────────────────────────────────────────
// main.dart
//
// Application bootstrap. Everything below is intentionally minimal — the
// interesting logic (AR overlay, WebSocket, audio) lives in feature folders.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'state/locale_provider.dart';

void main() {
  // `runApp` drives the whole Flutter lifecycle; there's no async setup that
  // needs to block the first frame, so we don't use WidgetsFlutterBinding here.
  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: const CoachingApp(),
    ),
  );
}

/// Root widget. Dark theme picked deliberately: a bright white app at the
/// start of a dim-lit home workout is uncomfortable, and it also leaves more
/// visual room for the red pulse animation used to flag form faults.
class CoachingApp extends StatelessWidget {
  const CoachingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, child) {
        return MaterialApp(
          // Dynamically read title from translations if needed, or fallback.
          title: localeProvider.t('app_title'),
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00E676), // Same green as the AR overlay.
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          builder: (context, child) {
            return Directionality(
              textDirection: localeProvider.isRtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child!,
            );
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}
