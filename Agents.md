# Flutter project rules

- Do not run `flutter analyze` directly from Codex unless explicitly requested.
- Prefer manual code inspection for Dart/Flutter issues.
- If validation is required, ask the user to run:
  flutter analyze --no-pub
- Do not run long-running Flutter commands in parallel.
- Keep changes minimal and limited to the requested files.