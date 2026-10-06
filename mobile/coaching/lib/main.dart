// ─────────────────────────────────────────────────────────────────────────────
// main.dart
//
// Application bootstrap. Everything below is intentionally minimal — the
// interesting logic (prayer engine, pose detection, guidance) lives in feature
// folders.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'state/locale_provider.dart';
import 'ui/app_theme.dart';
import 'config/env.dart';
import 'accounts/controller.dart';
import 'accounts/platform.dart';

Future<void> main() async {
  // Read a one-time child pairing link before MaterialApp normalizes the URL.
  final startupPairingCode = initialAccountPairingCode();
  // Restore the test endpoint before any backend client is constructed.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Env.load();
  } catch (_) {/* Use the build default if storage is unavailable. */}
  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: CoachingApp(startupPairingCode: startupPairingCode),
    ),
  );
}

/// Root widget: shared Arabic RTL theme for Android and responsive Web.
class CoachingApp extends StatelessWidget {
  const CoachingApp({super.key, this.startupPairingCode});

  final String? startupPairingCode;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AccountController(startupPairingCode: startupPairingCode)
        ..initialize(),
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) {
          return MaterialApp(
            // Dynamically read title from translations if needed, or fallback.
            title: 'اقتدِ',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
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
      ),
    );
  }
}
