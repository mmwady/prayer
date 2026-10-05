# Optional monitoring impact and protected baseline

Inspected before source changes (2026-10-05): `mobile/coaching` is the Flutter
project. `main.dart` -> Provider LocaleProvider -> HomeScreen -> Navigator
MaterialPageRoute. No routing/state management replacement is needed.
Home selects all six PrayerCatalog entries. VideoAnalysisScreen and
LiveAnalysisScreen instantiate local analysis services. Camera and supported
local video extraction feed LocalSession -> conditional native/web provider.
Android's LocalInferenceChannel and Web's same-origin recognizer worker own
letterboxing, Heavy Pose Landmarker, 166 features and three ONNX models.
`local/report_engine.dart` with opt-in correction/sequence modules produces
AnalysisReport; `LocalSession.complete()` is the final report/save boundary.
Local evidence/history use Android files/Web IndexedDB; settings use
SharedPreferences. Standalone browser image recognizer is an independent path.

FastAPI uses Settings/get_settings, routers and SQLite for Mosque Companion.
Legacy server analysis/reference tools remain isolated; no SQLAlchemy/Alembic
migration framework or authentication provider exists. New monitoring uses a
separate additive SQLite database, existing HTTP and Navigator/Provider patterns.

Protected source snapshot is recorded in `output/accounts/protected-before.json`.
Baseline analyzer is run before adding dependencies. Existing user changes are
extensive and are preserved. This task never resets the checkout.

Planned edits: optional home account entry and greeting, startup of a background
account controller without awaiting network, one callback after the local final
report, backend router/config registration and dependency manifests. All new
domain/UI/storage/queue/API logic belongs to accounts modules. No models,
preprocessing, detectors, sequence assessment or native inference are edited.

Following the user's explicit correction, all authentication is backend-only.
FastAPI uses pwdlib Argon2id hashing, SMTP verification/reset email and hashed,
revocable opaque sessions. There is no Firebase/provider dependency. Android tokens use secure storage;
Web uses HttpOnly SameSite cookies (same-site deployment and explicit origins).
No inference bytes are passed to the account adapter. The callback receives a
strict scalar summary only. REVIEW_REQUIRED stays uncertain; synthetic/demo
reports never sync. Recorded input time means analysis completion time, not
unverifiable historical capture time, disclosed in UI.
