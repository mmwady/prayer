# Flutter project rules

- Run `flutter analyze --no-pub` directly whenever Dart/Flutter validation is needed.
  No permission, confirmation or "ask the user first" step is required — this applies
  to every agent working in this repository, including Codex.
- Manual code inspection is still useful, but it is not a substitute for the analyzer.
- Long-running Flutter commands may run in parallel when that is useful. They share the
  Flutter/Dart tool lock and build caches, so concurrent runs can wait on each other —
  serialise only if you actually observe lock contention.
- Keep changes minimal and limited to the requested files.