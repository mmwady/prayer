// ─────────────────────────────────────────────────────────────────────────────
// env.dart
//
// Centralized runtime configuration for the Flutter app.
//
// Using `--dart-define` flags keeps the WebSocket URL out of source control
// and lets CI produce per-flavor builds (dev / staging / prod) without
// separate code paths. Example:
//   flutter run --dart-define=WS_URL=ws://192.168.1.10:8000/ws/coach
// ─────────────────────────────────────────────────────────────────────────────

class Env {
  // Private constructor — this class is a namespace, not a value.
  const Env._();

  /// Backend WebSocket URL. Default points at a dev server on the loopback
  /// as seen from an Android emulator (10.0.2.2 is the emulator's host alias).
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://127.0.0.1:8000/ws/coach',
  );

  /// Exercises the UI exposes from the home screen. The backend treats these
  /// as opaque strings, so adding a new one here just requires a matching
  /// form rule in [FormAnalyzer].
  static const List<String> exercises = [
    'squat',
    'pushup',
    'deadlift',
  ];
}
