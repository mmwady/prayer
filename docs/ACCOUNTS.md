# Optional accounts and monitoring

Implemented 2026-10-05. Authentication runs entirely on the existing FastAPI
backend. No Firebase is used. Prayer analysis happens locally on the user's device.

## Architecture and protected boundary

The existing Provider/Navigator Flutter application remains the entry point.
`AccountController` starts in the background; the offline prayer cards do not wait
for login, pairing, network, or the backend. An optional home tile opens accounts.
Paired children see their name without an extra step before prayer selection.

The selected-prayer video/live path produces its final `AnalysisReport` in
`LocalSession.complete()`. After the original report is calculated and stored, a
small adapter enqueues scalar metadata. It captures the child/backend binding at
session creation. The controller never receives frames, landmarks, feature arrays,
tensors, model probabilities, or the report/evidence object. Synthetic reports
are excluded; `REVIEW_REQUIRED` becomes uncertainty and receives no success points.
The separate standalone browser image recognizer keeps its original local report
path and does not synchronize. See `ACCOUNT_IMPACT.md` for pre-edit inspection.

MediaPipe, letterboxing, 166-feature preprocessing, three ONNX models, ensemble
predictions, optional corrections and deterministic sequence/rakah assessment were
not changed. Existing legacy backend analysis tools remain separate; the new
account flow does not invoke them or introduce remote inference.

## Exact implementation files

Added:

- `backend/app/accounts/{__init__,api,auth,boundary,domain,store}.py`
- `backend/tests/test_accounts.py`
- `backend/tools/account_demo_server.py`
- `backend/tools/seed_account_demo.py`
- `mobile/coaching/lib/accounts/{client,controller,platform,platform_native,platform_web,screen,sync_adapter}.dart`
- `mobile/coaching/test/accounts_test.dart`
- `mobile/coaching/browser/scripts/verify-accounts.mjs`
- `docs/ACCOUNT_IMPACT.md` and this document

Modified for this feature (the checkout also contains extensive pre-existing work):

- `.env.example`, `.gitignore`
- `backend/app/config.py`, `backend/app/main.py`
- `backend/requirements.txt`, `backend/pyproject.toml`
- `backend/tools/tunnel_gateway.py`, `backend/tests/test_tunnel_gateway.py`
- `mobile/coaching/pubspec.yaml`, `mobile/coaching/pubspec.lock`
- `mobile/coaching/lib/main.dart`, `mobile/coaching/lib/screens/home_screen.dart`
- `mobile/coaching/lib/local/session.dart` (post-result adapter only)
- `mobile/coaching/android/app/src/main/res/xml/local_backup_rules.xml`
- `mobile/coaching/android/app/src/main/res/xml/local_data_extraction_rules.xml`
- `mobile/coaching/linux/flutter/generated_plugin_registrant.cc` (package generation)
- `.copilotarch/INDEX.md`, `.copilotarch/FEATURE_MAP.md`, `.copilotarch/CURRENT_STATE.md`

Build outputs and acceptance evidence under `output/accounts` are development
artifacts. Model files and the locked browser inference manifest are untouched.

## Database

`ACCOUNT_DB`, default `backend/data/accounts.sqlite3` relative to backend launch
directory, is separate from Mosque/analysis data. SQLite schema version 1 creates
tables/indexes additively: `guardians`, `guardian_sessions`, `email_tokens`,
`groups`, `children`, `pairing_tokens`, `devices`, `attempts`, `rate_limits`,
`account_schema`. Foreign keys are enabled. `UNIQUE(child_id,client_attempt_id)`
enforces idempotency. Redemption/revocation/insertion use database transactions.
No existing migration framework is present, so there is no Alembic migration or
destructive schema change. Back up this database; reverting the optional router
can leave it safely in place. Future schema changes must version the schema.

## Dependencies

Backend: `pwdlib[argon2]` for mature Argon2id password hashing,
`email-validator` for validated email addresses, and `tzdata` for portable IANA
timezones on Windows and deployment images. Flutter: `flutter_secure_storage`
10.0.0 for native encrypted session storage, `qr_flutter` 4.1.0 for temporary QR
rendering, `mobile_scanner` 7.2.0 for Android/browser camera scanning. Existing
`http`, Provider, SharedPreferences and theme components are reused. Version 10
secure storage preserves compatibility with the project's existing JS dependency.
No state/routing/inference framework was migrated.

Library references: [FastAPI password hashing guidance](https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/#hash-and-verify-the-passwords)
and [flutter_secure_storage documentation](https://pub.dev/packages/flutter_secure_storage).

## API

All paths below have prefix `/api/v1/accounts`. Account requests require
`X-Iqtadi-Account: 1`; web uses `X-Iqtadi-Platform: web`. All private responses
are `Cache-Control: no-store`; bodies are limited to 16 KiB.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/config` | Email configuration availability only |
| POST | `/auth/signup` | Parent/teacher registration |
| POST | `/auth/resend`, `/auth/recover` | Verification/reset email |
| POST | `/auth/verify`, `/auth/reset` | One-use email token redemption |
| GET | `/auth/action` | Backend-hosted verification/reset page |
| POST, DELETE | `/session` | Guardian login/logout |
| GET | `/me` | Validated guardian identity |
| GET, POST | `/groups` | Owner groups/create family or classroom |
| PUT | `/groups/{id}` | Name/timezone/reviewed schedule |
| POST | `/groups/{id}/children` | Add child/student |
| PUT | `/children/{id}` | Edit/deactivate profile |
| POST | `/children/{id}/pairing` | Owner issues temporary QR/code |
| POST | `/pairing/redeem` | Exchange QR/code for child device session |
| GET, DELETE | `/device` | Child session identity/disconnect |
| GET | `/children/{id}/devices` | Owner lists child devices |
| DELETE | `/children/{id}/devices/{device_id}` | Owner revokes device |
| POST | `/attempts` | Device-scoped scalar result, idempotent |
| GET | `/groups/{id}/progress?day=YYYY-MM-DD` | Daily progress, rolling seven days, leaderboard/streak |

## Authentication and pairing

Passwords are Argon2id hashes, never plaintext. Email confirmation is required
before login. Verification and recovery tokens are random, hashed at rest,
expire after 30 minutes, and are single use. Reset revokes existing guardian
sessions. SMTP uses STARTTLS. Email links carry tokens in the URL fragment;
the backend page clears it and explicitly POSTs the action. A GET cannot consume
the token. The page sends no referrer and disallows framing.

Guardian sessions are random opaque tokens, hashed server-side, expiring in 30
days. Child sessions expire in 180 days and can be revoked immediately. Android
stores bearer tokens in secure storage and excludes that store from backups.
Web uses HttpOnly, Secure, SameSite=Strict cookies scoped to the account API;
JavaScript/localStorage does not store authentication tokens. Guardian and child
sessions are independent. Expiration requires login/re-pairing; there is no silent
refresh-token rotation in this MVP.

Pairing uses a cryptographically random 32-byte QR token and a separate random
10-character manual code. Both are hashed; neither contains a name, child ID or
permanent session. They expire in five minutes, bind to one child, and redeem
once atomically. Creating another code invalidates the earlier outstanding one.
Manual entry is always available on Android and Web, including camera denial.
Camera scanning uses the plugin with a user-friendly error fallback.

Server ownership checks protect every group/child/dashboard/device action. Role
determines group type. A child can submit only for the child assigned by its
validated session; client-supplied child/user IDs are rejected. Revocation is
rechecked within the insert transaction. Deactivation revokes devices and codes.
Login, email and pairing attempts are rate limited in SQLite, including failures.
Explicit allowed origins plus a custom non-simple header protect cookie APIs
against cross-origin submissions. Production deployments must use HTTPS.

## Queue and privacy

Minimal result entries persist locally in SharedPreferences, scoped to backend
and child: client attempt ID, prayer, completion timestamp, observed completion,
sequence validity, uncertainty, rakah counts, optional scalar confidence and
analysis version. A strict key/type allowlist rejects nested data. Tokens are
stored separately. No raw visual/model data is sent to accounts or analytics.
Enqueue is awaited before finishing the report screen; network failure does not
block recognition. Serialized writes avoid races; retries occur every 30 seconds,
on initialization, and manually. Only a successful acknowledged response
removes an entry. A lost ACK retries the same ID. Revoked sessions retain queued
entries, cannot sync, and cannot reassign old entries to a newly paired child.
Pairing the same child again permits retrying its pending entries.

The existing session identifier is stable across retry; backend uniqueness is per
child. Clear browser/app storage can erase pending results, so export local reports
before clearing storage. Invalid non-retryable responses remain visible as errors
and pending entries; automatic pruning is not implemented.

## Timing, progress, scoring

`domain.py` centralizes deterministic `PrayerTimeService` and progress rules.
The guardian enters an approved city timetable (HH:MM, IANA timezone, inclusive
date range up to 32 days). No continuous GPS, external time API, or LLM is used.
Fajr ends at sunrise; Dhuhr/Asr/Maghrib at the next prayer; Isha ends at the next
Fajr. After-midnight Isha belongs to the prior prayer day. Outside the configured
range timing is unknown, no on-time bonus is awarded, and missing prayers are not
prematurely marked missed. An attempt before its window also counts outside time.

Each distinct correct observed prayer earns 5 points; on-time adds 2; all five
correct adds 3. Repeated attempts cannot accumulate extra points. There is no
penalty. A completed day means all five correctly observed; consecutive completed
days form the streak. An unfinished today preserves yesterday's streak. Weekly
means rolling seven local calendar days including the selected day.

These are movement observations for encouragement, not a religious validity
judgment. Review/uncertainty never becomes success. Video attempts use analysis
completion time, not an unverifiable original recording date; the UI discloses
this. Automatic astronomical calculation methods and verified video capture
timestamps are deferred. No schedule default is fabricated.

## Running locally and deploying

Install backend dependencies in its venv, then use the existing FastAPI startup.
Configure `ACCOUNT_PUBLIC_URL`, `ACCOUNT_ALLOWED_ORIGINS`, SMTP host/port/user/
password/from and `ACCOUNT_DB` from `.env.example`. Production email requires
real SMTP configuration. For local development only, set
`ACCOUNT_MAIL_MODE=development`; protected `.eml` files are written to
`ACCOUNT_MAIL_OUTBOX`, not returned by APIs or publicly served.

Prefer Web and API on the same HTTPS origin, reverse-proxying `/api/v1/accounts`.
SameSite=Strict requires a same-site Web/API deployment; unrelated hosting domains
will not persist cookies. Set exact allowed origins. `ACCOUNT_SECURE_COOKIES=false`
is only for explicit local HTTP testing. Android uses the app's existing backend
URL setting; a backend URL change requires restarting the account controller/app.
The existing tunnel gateway forwards account routes while retaining operator
route restrictions. Do not expose the development email outbox.

After `flutter build web --no-pub`, run
`node browser/scripts/build-offline.mjs` in `mobile/coaching` using the existing
offline-cache packaging procedure. It packages existing inference assets; it does
not regenerate or convert ONNX models. Test helper:
`python -m uvicorn tools.account_demo_server:app --host 127.0.0.1 --port 8000`
from `backend`, with explicit dev DB/outbox settings. Its static server handles
`.mjs`/WASM MIME types for the existing local models.

Developer seed: `python -m tools.seed_account_demo --db data/family.demo.sqlite3`.
It requires a separate empty `.demo.sqlite3` file, prompts for a password, creates
an unverified Mohamed DEMO and labelled synthetic Omar/Ali/Youssef history. Normal
verification/login remain required. It never seeds a running real account DB.

## Verification and limits

See `output/accounts/VERIFICATION.md` for final command results and runtime evidence.
The browser acceptance harness is `browser/scripts/verify-accounts.mjs`; it uses
real Chrome, real Flutter, real backend auth and real local MediaPipe/ONNX on a
short recorded video. A review-required incomplete video is intentional test
evidence, not a complete prayer. Physical camera scanning and Android runtime
verification require real camera/device access and are separately reported.

Security tests cover expiration/reuse/invalid pairing, owner isolation, child
scope, revocation, duplicate sync, unauthenticated endpoints, cookie origin/header
protection, recovery/session invalidation, rate limiting, result consistency,
scalar privacy and request body limits. Flutter tests cover persistent offline
queue, lost ACK, duplicate/race/revocation binding, synthetic exclusion and
responsive account/manual-entry screens at 320/390/1024 pixels.

Remaining MVP limits: timetable is manual; owner-only group management (no
co-teacher invites); no dedicated retired-profile recovery UI; finite sessions
require re-login/re-pairing; standalone image recognizer does not synchronize;
browser cache must finish its first online setup before offline inference; queue
uses existing local preferences rather than an encrypted result database.
