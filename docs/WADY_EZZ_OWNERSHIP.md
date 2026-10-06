# Semantic integration ownership map

Inspected before implementation, 2026-10-06. Remote names are case-sensitive:
`origin/wady` = `b20b441`; `origin/Ezz` = `59457c4`;
starting main = `429bf41`; common ancestor = `970f6f6`.
The original checkout has local edits and is preserved in place. Integration uses
`integration/wady-ezz` in an isolated checkout; no production database is used.

## WADY_AUTHORITATIVE

- `mobile/coaching/lib/{prayer,state,pose,local,live,video,browser}/`: prayer definitions,
  sources, calibration, inference, raw/corrected assessment, rakahs, uncertainty,
  scores, report/history/evidence/export, live capture and model readiness.
- Prayer screens under `mobile/coaching/lib/screens/`, including video/live,
  local sessions and references. Shared home is integrated separately.
- `mobile/coaching/browser/{src,assets,test,tools}/`, including all model bytes,
  metadata, preprocessing, manifest, initialization deadlines/download progress.
- `model/`, `PrayerActionRecognizer_UI/`, Android native inference/image/math,
  camera/video pipeline, JNI/R8 rules, model packaging and parity fixtures.
- Prayer-specific guidance, geometry, references and UI dependencies. Unchanged
  shared source blobs are verified against both branches.

## EZZ_AUTHORITATIVE

- `backend/`: FastAPI architecture, API, security, repositories/storage,
  configuration, dependencies, tests, tools and all existing migrations.
- `backend/app/accounts/{auth,boundary,community}.py`: unified registration,
  verification/recovery, email providers, sessions, roles, families, consent,
  mosque groups/approval/messages/attendance/privacy and administration.
- `backend/app/mosque/`, `mobile/coaching/lib/mosque/`: complete companion demo.
- `mobile/coaching/lib/accounts/`: authentication, personal profile, dependent
  pairing/deep links, guardian/family/mosque UI, queue/token/session management.
- Ezz account documentation, account test suites, QR acceptance script and LAN
  debug-only cleartext configuration.

## SHARED_NEEDS_INTEGRATION

| Files | Integration decision |
| --- | --- |
| `backend/app/accounts/api.py` | Ezz identity/authorization/API plus optional validated Wady movement summary fields, explicit-column persistence and existing score tie breaker. |
| `backend/app/accounts/store.py` | All Ezz schema/migrations; add nullable movement columns in a separate schema version 3. Preserve databases upgraded from either branch's distinct version 2. |
| `backend/app/accounts/domain.py` | Ezz timing/positive points/streaks plus Wady additive coverage aggregation; coverage never changes uncertainty or success. |
| `lib/accounts/controller.dart` | Ezz auth/pairing/session behavior; extend scalar allowlist to preserve Wady final coverage fields. |
| Account/family dashboard UI | Preserve Ezz navigation/identity UI, expose Wady movement scores with nullable legacy handling and independent review state. |
| `lib/main.dart` | Combine Ezz startup pairing-code handling and existing Wady Provider/theme/app bootstrap. |
| `lib/screens/home_screen.dart` | Preserve all prayer cards/local screens, Ezz account hub/image/reference entries and complete companion screen access. Ezz's placeholder must not make its existing companion implementation inaccessible. |
| `lib/config/env.dart` | Same-origin Web default from both branches; retain explicit build endpoint and saved override precedence. |
| pubspec/lock, Python dependencies | Compare directly; retain union of authoritative requirements. No model dependency removal. |
| Android/Web configuration | Preserve Wady inference/camera/offline caching and Ezz debug account connectivity. Regenerate plugin files through Flutter. |
| tests/docs/architecture | Union authoritative assertions; adapt account fixtures for schema-safe explicit-column inserts. Record all limitations. |
| deployment | Retain Wady operational deployment scripts. Extend proxy API coverage if Ezz added routes require it; do not deploy during integration. |

## LEGACY_OR_REDUNDANT

No application logic is scheduled for deletion. Retained backend analysis tools
are explicit compatibility workflows, not default local prayer routes. Companion
demo remains labelled simulated and enabled only by its existing explicit flag.

## Contract audit before edits

- `user_id`/guardian identity: server-owned `guardians.id`, hashed opaque session.
  Parent authority comes from family membership/guardian links; mosque staff is
  never automatically a guardian. `child_id` includes a SELF practice profile or
  paired DEPENDENT and is resolved from the validated device session.
- Stable local session ID maps to `client_attempt_id`; backend generates attempt
  `id`, with uniqueness by child and client attempt. No fabricated IDs.
- Prayer enum is `fajr|dhuhr|asr|maghrib|isha`, 2/4/4/3/4 rakahs; `demo` and
  synthetic reports are excluded. Wady station/action/rakah detail stays local.
- `valid` means `OBSERVED_COMPLETE`, never religious validity. `sequence_valid`
  follows that final observation; `REVIEW_REQUIRED` maps to uncertainty and earns
  no success points. Missed/order/action confidence/raw predictions remain in
  the local report; optional scalar confidence is nullable, no inference upload.
- `performed_at` is timezone-aware analysis completion time, not original video
  capture time. Start/frame times remain local; stored backend `created_at` is UTC.
- Final coverage is detected/expected station count and percentage, independent
  of positive account points, on-time bonus and streak. Three optional scalar
  fields must appear together and agree mathematically; old attempts stay null.
- Binding includes backend endpoint and profile; captured at session creation.
  Queue is persistent/idempotent and never reassigned to a different child.
- Mosque group/attendance/session identifiers stay in Ezz's independent APIs;
  attendance ranking must not become camera-practice scoring.
- Web uses HttpOnly Secure SameSite cookies; native uses secure storage; no
  tokens or model inputs are added to final-result DTOs.

## Protected prayer flow

Prayer cards -> local video/live service -> local session -> Web worker or native
Android CPU -> EXIF/RGB/384x512 letterbox/recovery -> Heavy MediaPipe -> fixed
166 features -> 2026/3407/8111 ONNX models -> softmax each then mean probabilities
-> temporal/raw and optional normalized alignment -> rakah/station report and
coverage -> local repository -> scalar-only account adapter. Preserve class order,
three-stable-match capture, error/retry/cancellation and all uncertainty evidence.
