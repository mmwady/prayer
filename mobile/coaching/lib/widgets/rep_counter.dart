// ─────────────────────────────────────────────────────────────────────────────
// rep_counter.dart
//
// Minimal HUD element shown during a set. Deliberately plain — the user
// should be looking at their form, not a fancy UI.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class RepCounter extends StatelessWidget {
  const RepCounter({super.key, required this.reps});

  final int reps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // Semi-transparent pill so the number stays readable on any
      // camera background, without blocking too much of the frame.
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        '$reps',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.w700,
          // Tabular numerals keep the counter from jittering horizontally
          // as digits change width.
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
