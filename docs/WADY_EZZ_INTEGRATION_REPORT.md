# Wady / Ezz semantic integration report

Date: 2026-10-06. Integration branch: `integration/wady-ezz`.

**Main release gate is CLOSED.** The integrated application preserves the protected
domains, but inherited backend test/lint/type failures prevent a claim that all
required validation succeeds. `main`, `wady` and `Ezz` remain intact. No deployment,
production database operation, main merge or main push has been performed.
The integration branch is committed for review; failing checks do not authorize
a main update. The user explicitly authorized publishing only this review branch
to GitHub on 2026-10-06, following an earlier automatic approval rejection.
No merge into main, main push or deployment is authorized by this publication.

User-authorized follow-up, 2026-10-06: account email submission now uses an additive
schema-v4 durable outbox, leased retries, SMTP SSL/STARTTLS and signed Resend delivery
receipts. Authentication eligibility, roles/relationships and protected prayer rules
are preserved; the email transport/registration-response behavior intentionally
differs from the pinned Ezz version to fix commit ordering and outage recovery.
[Mail repair, setup and acceptance](ACCOUNT_EMAIL_DELIVERY.md) records the new
behavior and limits. The validation table below records the initial integration;
the mail follow-up has its own checks and does not reopen the main gate.

## Sources and ownership

Fetched GitHub before inspection. The actual remote branch is `Ezz`, case-sensitive.

| Source | Pinned commit | Preserved ownership |
| --- | --- | --- |
| `origin/wady` | `b20b441` | Complete local prayer selection/video/live/image recognition, model loading, inference, preprocessing, temporal/sequence/rakah rules, optional assessment, coverage scores, reports, evidence, history/export/delete, camera switching/countdown and preparation UX. |
| `origin/Ezz` | `59457c4` | Backend, authentication, email providers, identities/sessions, personal profiles, families/guardians/dependents, pairing/revocation, mosque groups/consent/leader approvals/messages/attendance, administration and companion implementation. |
| `origin/main` | `429bf41` | Integration starting point; no main update. |

`Ezz` was inspected first: account API/auth/store/community, relationship/permission
checks, session flow, Flutter controller/UI, documentation and persistence contract.
Then Wady's full local prayer flow and its source/tests/assets were traced.
[Ownership map](WADY_EZZ_OWNERSHIP.md) was written before the implementation merge.
No authoritative domain was selected solely by timestamps or whole-branch checkout.

## Git conflicts and resolution

Both histories are included in the integration merge. Five textual conflicts:

| File | Resolution |
| --- | --- |
| `backend/app/accounts/api.py` | Combined Ezz's personal-profile/auth import with Wady station-count validation; preserved all Ezz endpoints/security and added optional coverage fields. |
| `backend/tools/seed_account_demo.py` | Retained Ezz's complete isolated rich demo seed and its explicit-column attempt inserts, compatible with the extended schema. No production data was seeded. |
| `mobile/coaching/lib/accounts/screen.dart` | Preserved Ezz's unified account hub, child flow, pairing and navigation. Reintroduced Wady coverage presentation through a separate widget in personal/child/family views. |
| `mobile/coaching/lib/config/env.dart` | Kept same-origin Web default and retained saved override and explicit build endpoint precedence. |
| `mobile/coaching/lib/screens/home_screen.dart` | Combined all six Wady prayer cards with Ezz accounts, local references and Web image entry. Kept the complete companion screen accessible. |

Conflict markers were removed and the staged diff passed `git diff --check`.
Generated plugin registrants were produced by `flutter pub get`, not hand-edited.

## Semantic conflicts

- Both branches called distinct account changes schema version **2**. Integrated
  version **3** retains Ezz's entire relationship schema plus Wady's nullable
  movement columns. Upgrade checks use actual untouched store code from each
  pinned branch and synthetic isolated databases; existing rows, opaque sessions,
  devices, attempt IDs/values and foreign keys survive repeated migration.
- Ezz's result DTO and queue allowlist lacked Wady movement fields. The scalar
  integration boundary now preserves detected/expected counts and percentage;
  mismatched, partial, fractional or impossible counters are rejected.
- Ezz's `/device/progress` selected fields explicitly and would silently discard
  coverage after successful persistence. Coverage and its existing `week` contract
  now reach personal/child views; family progress keeps all Ezz relationship checks.
- The new family leaderboard preserves Wady's score tie breaker after existing
  encouragement points; coverage does not manufacture success points or remove
  review-required status. Mosque attendance and its ranking remain separate.
- Ezz's home change made its retained companion implementation inaccessible behind
  a “coming soon” placeholder. Navigation now exposes the existing labelled demo,
  with the same opt-in backend flag and all original privacy/workflow rules.
- Windows `core.autocrlf=true` changed manifest-hashed pipeline bytes in a fresh
  checkout. Narrow `.gitattributes` rules force LF for the hashed JS sources and
  npm lockfile. Every source/asset hash matches the original Wady manifest;
  **no models or preprocessing arrays were regenerated**.

## Cross-domain integration and data audit

Flow: Ezz authentication/profile context -> unchanged Wady `LocalSession` -> local
report/save -> scalar adapter/queue -> authenticated Ezz `/attempts` -> SQLite ->
personal/family progress. Models do not depend on authentication or backend DTOs.

| Concept | Final mapping / rules |
| --- | --- |
| Account / parent identity | Server-owned account/session; parent authority uses Ezz family memberships and guardian links. No client ID substitution. |
| Child / adult learner | Validated device session maps to DEPENDENT or SELF practice profile. Ownership and revocation are checked again in the insertion transaction. |
| Prayer session | Stable local ID -> `client_attempt_id`; server attempt `id`; unique `(child_id, client_attempt_id)` preserves retry idempotency. |
| Prayer type / rakahs | Lowercase five-prayer enum, counts 2/4/4/3/4. Demo/synthetic reports never sync. Rakah/action detail remains local. |
| Movement/confidence/order | All eight classes, raw individual model probabilities, evidence, missed/out-of-order actions and uncertain station assignments remain in Wady reports. Optional scalar confidence remains nullable; no raw model output upload. |
| Validity / uncertainty | `OBSERVED_COMPLETE` maps to observed `valid`/`sequence_valid`; `REVIEW_REQUIRED` remains uncertainty with no success points. Neither is a religious ruling. |
| Final score | Wady detected/expected station coverage and percentage; distinct from Ezz points, timing bonus and streaks. All three optional fields must agree; old attempts remain null. |
| Timestamps | `performed_at` is timezone-aware analysis completion time. Backend `created_at` is UTC. Original recording/start/frame times stay local and are not fabricated as capture-time evidence. |
| Synchronization | Persistent scalar queue scoped by endpoint/profile, frozen binding at session creation, retry-safe ACK removal and session revocation handling remain intact. No dummy identity or mock default added. |
| Mosque identifiers | Mosque/group/invitation/attendance/session IDs stay in Ezz APIs with consent and distinct ranking. Staff roles never become guardian authority. |
| Tokens | Ezz hashed opaque sessions, Web HttpOnly cookies, native secure storage, pairing expiry/reuse checks, renewal/revocation, logout/recovery and headers/origin protections remain intact. |

There is no frame, image, pose-landmark, feature-array or tensor upload in default
prayer workflows. Retained legacy backend analysis tools require explicit use.
No new dependencies were needed: Flutter manifests/lockfile and Python dependency
files already match between the two authoritative branches. Operational deployment
scripts from Wady were retained; their `/api/` proxy already covers Ezz's routes.

## Protection evidence

- **141 protected tracked files** are Git-blob identical to `origin/wady`, including
  prayer source, tests, native core/packaging, model files and shared dependencies.
- Every Wady manifest asset and pipeline SHA-256 matches the integrated bytes.
- Preprocessing, recovery order, fixed classes, 166 features, individual softmax
  then mean ensemble, temporal/sequence/rakah rules, score calculation and offline
  behavior are preserved. No protected prayer source file was edited.
- Latest Ezz `auth.py`, `boundary.py`, settings, app/router bootstrap and all
  authentication behavior are preserved. Ezz `community.py` differs only by the
  additive family score tie breaker; no consent/role/message/attendance path lost.
- Companion backend and Flutter feature folders are unchanged from Ezz.

## Validation

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Backend complete pytest suite | FAIL | **184 passed, 4 failed** in 246.99s on the final idle run. Four unchanged boundary expectations also fail on untouched Ezz. `output/backend-tests-idle.log`. |
| New semantic API tests + existing consent check | PASS | 3 passed; personal/family association, score/uncertainty, idempotency, spoofed IDs, ranking and guardian consent. `output/integration-tests.log`. |
| Backend Ruff | FAIL | 212 diagnostics, exactly 212 on untouched Ezz too; no new diagnostic. `output/backend-lint-final.log`, `output/baseline-lint.log`. |
| Backend mypy | FAIL | Five errors in four files, identical to Ezz baseline: MediaPipe lacks typing, LLM messages typing, optional live connection, admin frames annotation. `output/backend-types.log`, `output/baseline-types.log`. |
| Backend startup / database | PASS | Real FastAPI startup and authenticated writes on isolated SQLite; no production DB touched. |
| Migration / integrity | PASS | Both pinned source schemas upgraded twice; rows/session values, foreign keys and Wady 75% / Ezz null legacy score retained. `output/migration-audit.json`. |
| Flutter pub get | PASS | Locked dependencies; no package upgrades. |
| Flutter analyze --no-pub | PASS for errors/warnings | Zero errors/warnings; six inherited informational diagnostics retained. Default fatal-info behavior is not a clean zero-diagnostic check. `output/flutter-analyze-final.log`. |
| Flutter complete tests | PASS | 151 passed on the idle full suite, including two new coverage widget tests. `output/flutter-tests-idle.log`. |
| Browser model unit tests / bundle | PASS | 34 tests, successful npm build, exact pinned hashes; original generated parity fixtures supplied locally. `output/browser-tests.log`. |
| Flutter Web release | PASS | `flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn`, then offline manifest: 78 files / 126,837,030 bytes. `output/web-build.log`. |
| Android debug APK | PASS | `flutter build apk --debug --no-pub`; existing Java 8/ML Kit compiler warnings. `output/android-build.log`. |
| Packaged model audit | PASS | All seven required native model/manifest files plus ONNX/MediaPipe native libraries; all eight Web model/export assets match SHA-256. `output/packaged-model-audit.json`. |
| Browser authentication / parent-child | PASS | Existing Ezz QR acceptance harness: real login, dependent pairing/reload, correct profile and group context, parent revocation clears device and pairing URL. Isolated explicit demo identities. `output/e2e/pairing-browser.log`. |
| Browser prayer / persistence / companion | PASS | Rendered Chrome login, family/mosque group views, six prayer routes; fully offline 16-frame real video through Heavy MediaPipe + three ONNX models; REVIEW_REQUIRED 12.5% result persisted to the right SELF profile, duplicate retry acknowledged, cookie session survives reload. Existing labelled companion demo creates a request and opens matching results. Zero JavaScript errors, no frame/landmark/model-input HTTP uploads. `output/e2e/semantic-browser.json`. |

Screenshots were inspected: account hub, family, mosque groups, offline prayer
report/evidence and companion. Acceptance uses the real production code with an
explicitly isolated seeded demonstration database and development email outbox;
reported sample points are seed data, not invented prayer scores. Local video
score is real inference, not synthetic. No external emails/notifications or paid
model requests were made.

Heavy concurrent Android build load caused transient failures in unchanged live
Flutter tests (200ms polling budget) and one backend buffering test (5s gate).
The idle Flutter suite passes all 151; the isolated backend buffering rerun passes
in 9.30 seconds. No test budgets or protected source were weakened to pass.

## Remaining risks / acceptance limits

- Four inherited boundary-test disagreements and inherited lint/type failures
  keep the main gate closed. See the exact boundary conflict below.
- Physical Android camera/inference, a physical child-device lifecycle and full
  companion two-person confirmation/navigation were not exercised in this run.
  Building and package hashes are separate from physical-device acceptance.
- SMTP delivery/verification and production deployment/network/database have not
  been exercised; development verification fixtures are explicit, not default
  production authentication bypasses.
- Companion remains the original opt-in simulated implementation. Routing,
  addresses and demo identities are not claimed as verified real-world service.
- Offline video/profile scalar sync is verified in Chrome. Camera permissions,
  real live-camera motion and other browser/hardware combinations remain separate
  acceptance checks; existing logic/tests were preserved.

Detailed local logs and screenshots live under ignored `output/`; no videos,
database, credentials, generated model fixtures or build products are committed.

## Known inherited blocker: prayer boundary tests

The following four backend cases fail on the **untouched Ezz source** and on the
integrated unchanged prayer backend:

- `test_confirmed_boundary_anchors_next_standing_even_when_bowing_is_missing`
- `test_floor_sequence_independent_of_missing_bowing_and_duplicate_samples[False]`
- `test_floor_sequence_independent_of_missing_bowing_and_duplicate_samples[True]`
- `test_false_early_sitting_and_salam_cannot_advance_the_rakah`

These tests expect the next rakah to be inferred in sequences without a
standing/ruku/standing transition. Current protected normalization requires that
transition after floor/seated observations before creating the next boundary.
Both branches have identical `sequence.py` and this test file. Reproducing the
baseline gives **4 failed, 31 deselected**. Integration did not introduce this
disagreement. Changing the rule could undo the conservative recovery behavior;
weakening/deleting tests merely to pass would hide the disagreement.

The integration branch is retained for review. Resolve the intended boundary
contract deliberately before reopening the main release gate. Existing backend
lint/type diagnostics also remain a failing check, not a claimed PASS.
