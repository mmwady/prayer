// ─────────────────────────────────────────────────────────────────────────────
// home_screen.dart
//
// Landing screen. Lets the user pick an exercise, then navigates to the
// [WorkoutScreen]. Intentionally tiny — once the user starts a set, the
// app becomes a single immersive camera view.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../state/locale_provider.dart';
import 'workout_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.t('app_title')),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: locale.localeCode,
              icon: const Icon(Icons.language, color: Colors.white),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  context.read<LocaleProvider>().setLocale(newValue);
                }
              },
              items: [
                DropdownMenuItem(
                  value: 'en',
                  child: Text(locale.t('english')),
                ),
                DropdownMenuItem(
                  value: 'ar',
                  child: Text(locale.t('arabic')),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const SizedBox(height: 16),
            Text(
              locale.t('pick_exercise'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            for (final ex in Env.exercises)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkoutScreen(exercise: ex),
                    ),
                  ),
                  child: Text(
                    ex.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
