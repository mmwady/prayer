# اقتدِ — Iqtadi

Arabic-first prayer training with the existing Flutter interface. Images, local
videos, camera recognition, three-model classification, sequence reports,
references, Arabic cues and session history run on-device. Mosque Companion and
optional accounts/family/classroom monitoring use the backend. Monitoring sends
only final scalar results, never images, landmarks or model tensors. Reports
describe observed movement coverage; they do not judge religious validity,
intention, recitation or acceptance.

## Project in 60 seconds

```text
Flutter: select prayer + local video/camera/image
    ↓ same-device decoding, oriented RGB, black letterbox and Heavy MediaPipe
166 float32 features → 3 unchanged ONNX classifiers
    ↓ separate softmax distributions → arithmetic probability mean
local temporal events → deterministic sequence alignment
    ↓
Arabic RTL report + three individual decisions + local evidence/history/export
```

Web uses a same-origin WASM worker with an on-device main-thread fallback.
Android uses a native CPU channel and bundles the same models. Existing six
prayer cards and report layouts are retained; the separate local geometry
trainer and clearly labelled synthetic demo remain available in source.
Native iOS/desktop inference is unsupported. Selected Android CPU and recorded-video
flows have been tested on a Samsung M52; live-camera and other-device acceptance
remain incomplete. See the measured results below.

## Core concepts and main blocks

| Block | Responsibility | Main location |
|---|---|---|
| Browser recognizer | Exact preprocessing, Heavy landmarks, three ONNX probabilities | `mobile/coaching/browser/src/` |
| Android recognizer | Same preprocessing/models through a serial native channel | `android/app/src/main/kotlin/com/example/coaching/LocalInference*.kt` |
| Local session | Serial observations, stable capture, evidence selection and local save | `mobile/coaching/lib/local/session.dart` |
| Conservative report | Raw Python temporal/alignment semantics, ambiguity and review placement | `browser/src/session.mjs`, `lib/local/report_engine.dart` |
| Local history | Atomic IndexedDB or private Android files, export and explicit deletion | `lib/local/provider_*.dart`, `browser/src/storage.mjs` |
| Existing UI | Video/live progress, per-rakah evidence and all individual decisions | `lib/screens/{video,live}_analysis_screen.dart` |
| References and cues | Local reviewed reference JSON and static Arabic guidance | `lib/prayer/local_reference_*`, `lib/services/prayer_guidance_client.dart` |
| Mosque Companion | Existing optional backend demo integration | `backend/app/mosque/`, `lib/mosque/` |
| Accounts, families and mosque groups | Unified login, family roles, guardian consent, aliases, attendance and scalar-result synchronization | `backend/app/accounts/`, `lib/accounts/` |

Paths beginning `lib/`, `android/` and `browser/` are under `mobile/coaching/`.
Model weights/class order are unchanged. [Exact mathematical contract](docs/BROWSER_INFERENCE_SPEC.md).

## Typical flow and state

Choose Fajr → select a local video or open the camera → local models analyze
frames → review each rakah, uncertainty, images and three classifier decisions.
Completed reports survive navigation in **تقاريري على الجهاز**; delete removes
that report and its evidence. Source videos never enter saved history.
References can be imported, reviewed and activated in **المراجع المحلية**.
No trusted reference or religious verdict is invented.

Gallery auto-capture requires three consecutive confident matches; report
observations are retained independently. Live capture defaults to adaptive
throttling and never overlaps inference. Missing or ambiguous observations stay
`UNCONFIRMED`/`REVIEW_REQUIRED`. Probability confidence is not prayer validity.

History allows 10 sessions/128MB, selected evidence up to64MB. Full/denied storage
leaves the report visible and exportable, with a warning and no automatic removal
of older sessions. Prediction schema, model assets and native pipeline versions
invalidate incompatible cached sessions.

## If I want to change...

| Goal | Start here |
|---|---|
| Verify preprocessing/class ordering | `docs/BROWSER_INFERENCE_SPEC.md`, `browser/src/core.mjs` |
| Export unchanged classifiers | `browser/tools/export_models.py` |
| Change conservative report behavior | Python `backend/app/analysis/{temporal,sequence}.py` source; preserve JS/Dart parity |
| Change capture/sampling | `lib/live/live_controller.dart`, `lib/video/`, native camera/video bridges |
| Change history/retention | `lib/local/session.dart`, `browser/src/storage.mjs`, `provider_native.dart` |
| Change report layout | `lib/screens/video_analysis_screen.dart`, `lib/local/prediction_cards.dart` |
| Change design | `lib/ui/app_theme.dart`, `ui_kit.dart` |
| Configure Mosque Companion backend | `lib/config/env.dart`, its settings drawer, `backend/app/mosque/` |
| Change accounts or monitoring | `lib/accounts/`, `backend/app/accounts/`, `docs/ACCOUNTS.md` |

Recommended reading: exact inference contract → local service/session →
browser bridge or native channel → raw report engine → existing results UI.

## `Ezz` branch — connected accounts and community release

This branch starts from `origin/main` commit `970f6f6` and adds the connected
account, family and verified-mosque experience. It does **not** replace the
camera, local classifiers, prayer-action sequence engine, local evidence store
or prayer report semantics. Camera frames, video, landmarks and tensors remain
on the device; connected features receive only allowlisted scalar summaries.

### Unified accounts and real email boundaries

- One registration/login flow serves ordinary adults, parents, new Muslims,
  elderly learners and people who later receive a mosque role.
- Passwords require at least eight characters. Email verification, recovery,
  single-use expiring tokens, Argon2 hashes, rate limits and revocable sessions
  are enforced by the backend.
- Resend and SMTP are supported. Provider failures are never reported as
  success: invalid keys, unverified senders, test-recipient restrictions,
  provider rejection and rate limits have separate Arabic messages.
- `onboarding@resend.dev` is a Resend test sender and can send only to the
  Resend account owner's address. Public registration requires a verified
  custom domain or configured SMTP credentials.

### Personal practice and child-device pairing

- Every adult account receives a private `SELF` practice profile, including
  new-Muslim and accessibility preferences.
- A guardian adds a dependent, generates a one-use QR/code and the child's
  phone signs in without an email or password. The session persists until the
  child logs out, the guardian revokes the device, or the session expires.
- The family screen shows whether each child has no linked device or one or
  more active devices, their platform and last activity, with individual
  revocation controls.
- The child dashboard shows today's completion, weekly camera-practice points,
  completed prayers, streak and a separate card for every mosque-group rank.
  A child who logs out can sign in again only through a guardian-issued QR.

### Multiple families and scoped permissions

- An account may own or participate in multiple independent families. Changing
  a member's role in one family never changes their access in another family.
- Family roles are `OWNER`, `GUARDIAN`, `ADULT` and `SUPPORTER`. Owners can
  invite members, change non-owner roles and remove non-owners. Owners cannot
  accidentally demote or remove themselves.
- Only owners/guardians manage children, devices and guardian consent. Mosque
  leaders never become guardians merely because they teach a child.

### Verified mosque roles and groups

- A normal account can request a leader or mosque-administrator role. A
  platform administrator reviews and approves/rejects the request; users cannot
  self-assign privileged mosque access.
- The UI separates **personal mode** from **mosque-leader mode** even when one
  person has both perspectives.
- Adult and child groups are server-enforced categories. Adults cannot join a
  child group; children cannot join an adult group or the wrong child age band.
- Adults join for themselves. A guardian submits a child with explicit sharing
  choices, then a mosque leader accepts or rejects the pending request.
- A person or child can belong to several groups and the controlling adult can
  leave each membership independently.
- Attendance is a separate record from camera-practice scoring. Public mosque
  rankings use aliases or group totals and never expose identifiable child
  names.

### Adult group conversation

- Active members of an adult group have a compact **مجلس المجموعة** feed for
  short encouragement messages such as “I am on the way to the mosque—who will
  join me?” and threaded replies.
- Messages use the member's group alias, are limited to 280 characters and are
  available only to active adult `SELF` memberships. The server rejects access
  from child groups.
- The separate **رفيق المسجد** transport/companion prototype is disabled in
  the home screen and labelled **قريبًا**.

### Demo accounts and sample scenarios

Run the isolated seed command documented below. All demo accounts use
`eqtadi1234`:

| Purpose | Email |
|---|---|
| Platform administrator | `admin@example.com` |
| Mosque administrator/sheikh | `sheikh@example.com` |
| Parent, multiple-family owner and mosque leader | `demo@example.com` |
| Co-guardian | `guardian@example.com` |
| New-Muslim adult | `newmuslim@example.com` |
| Elderly/supporter profile | `elder@example.com` |

The seed includes multiple families, several child age bands, linked guardian
relationships, adult and child mosque groups, aliases, practice histories and
separate attendance histories. `tools/upgrade_account_demo_v3.py` adds the
administrator and second-family scenarios to an existing rich demo database
without replacing user-created records.

### Validation performed for this branch

- Account/authentication, family, consent, role approval, audience enforcement,
  attendance, child ranking and adult-chat backend tests pass.
- Flutter account and narrow-phone layout tests pass, and Flutter analysis is
  clean for changed account/community screens.
- Real browser acceptance covers QR child login, score retrieval, persistent
  device identity, one-time-secret removal and guardian revocation.
- Prayer/camera code paths were not repurposed by these features. Before release,
  run the unchanged inference, report-parity and privacy suites listed below in
  addition to the connected-account tests.

## Run from a fresh checkout (Windows / PowerShell)

Prerequisites: Git, Flutter with a compatible Dart SDK (the package requires Dart
`>=3.4.0 <4.0.0`), Node.js/npm, and Python 3.11. Android builds also need the
Android SDK and a JDK compatible with the project's Gradle setup. Use
`flutter doctor` to check the installed platform tools.

The Python environment prepares and validates model assets during the build;
no Python server is required for local prayer inference at runtime.

```powershell
git clone https://github.com/mmwady/prayer.git
cd prayer
py -3.11 -m venv backend/.venv
.\backend\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
.\backend\.venv\Scripts\python.exe -m pip install -r mobile/coaching/browser/tools/requirements-export.txt
cd mobile/coaching
flutter pub get
cd ../..
.\mobile\coaching\browser\build.ps1
```

The private repository requires GitHub access. The build script installs locked
npm dependencies, generates synthetic parity fixtures, exports/checks ONNX
models, runs browser tests and Flutter analysis, builds release Web assets, and
creates the offline cache manifest. Use `-SkipInstall` only after npm dependencies
have already been installed. Model bundles are included in the repository;
`mobile/coaching/web/recognizer/` and `mobile/coaching/build/` are generated locally.
The commands above describe the current build scripts; a new-machine dependency
installation has not been revalidated as part of this documentation update.

### Web

After the build, serve the complete Flutter distribution from repository root:

```powershell
node mobile/coaching/browser/scripts/serve.mjs mobile/coaching/build/web 8780
```

Open `http://127.0.0.1:8780/` for the Flutter app, or
`http://127.0.0.1:8780/recognizer/` for the standalone image recognizer. Keep the
terminal running. For interactive development after generating recognizer assets:

```powershell
cd mobile/coaching
flutter run -d chrome --web-port 8781
```

Publish the complete `mobile/coaching/build/web` directory over HTTPS. After any
later Flutter production build, regenerate its offline manifest:

```powershell
cd mobile/coaching
flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn
node browser/scripts/build-offline.mjs
```

First Web use downloads the app/model assets (about 127 MB in the documented
build). Wait for the offline-ready notice before disconnecting. Updates require
explicit activation; clearing browser storage can require another download.
Camera access requires HTTPS or localhost. Prayer inference and local history
work offline; connected account features and Mosque Companion require a server.
See [hosting/MIME details](docs/BROWSER_DEPLOYMENT.md).

### Android

After the initial setup, connect an Android device with USB debugging enabled
or start an emulator:

```powershell
cd mobile/coaching
flutter devices
flutter run -d <android-device-id>
# Or build an installable local APK:
flutter build apk --release --no-pub
```

Replace `<android-device-id>` with an ID from `flutter devices`. The APK is at
`mobile/coaching/build/app/outputs/flutter-apk/app-release.apk`. Gradle packages
models from `mobile/coaching/browser/assets/`; they are required even without a
backend. Current release builds use the existing debug signing configuration
for local testing; store publication needs production signing.

## Optional backend features

Prayer recognition, reports, references and static Arabic cues remain local.
The server provides optional accounts/monitoring and the explicitly simulated
Mosque Companion. Run it from repository root in a separate terminal:

```powershell
Copy-Item .env.example backend/.env
# Edit backend/.env before enabling connected features.
.\backend\start_backend.bat
```

Copy the template only when creating a new environment; preserve any existing
local configuration. Health check: `http://127.0.0.1:8000/healthz`.
For Docker, configure `backend/.env`, then run `docker compose up --build`.
Docker runs the backend; the Flutter app is built/run separately.

Configure the server address in the app's settings drawer or at build/run time:

```powershell
cd mobile/coaching
flutter run -d <android-device-id> --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

`10.0.2.2` reaches the host from an Android emulator. A physical phone uses the
computer's reachable LAN address; its `127.0.0.1` points to the phone itself.
For Web accounts, prefer a same-origin HTTPS reverse proxy and exact allowed
origins. Configure Resend or SMTP email verification, public URL and cookie
settings as explained in [accounts and monitoring](docs/ACCOUNTS.md). Email
verification is mandatory in every mode. The explicit development mode writes
to a private `.eml` outbox and the UI says that no email was sent. Passwords
require 8 characters.

For an isolated rich demo with verified sample accounts, family levels, children,
mosque groups, camera-practice scores and separate attendance history:

```powershell
cd backend
.\.venv\Scripts\python.exe -m tools.seed_account_demo --db data/accounts.rich.v2.demo.sqlite3
$env:ACCOUNT_DB = (Resolve-Path data/accounts.rich.v2.demo.sqlite3)
$env:ACCOUNT_SECURE_COOKIES = 'false'
.\.venv\Scripts\python.exe -m uvicorn tools.account_demo_server:app --host 127.0.0.1 --port 8000
```

Sign in with `demo@example.com` / `eqtadi1234`. The reusable group
invitation is `DEMOJOIN24`; today's separate attendance code is `FAJRDEMO`.
These deterministic credentials are for the isolated demo database only.

### Test from a phone on the same Wi-Fi

Build Web once, then run the LAN helper from the repository root:

```powershell
cd mobile/coaching
flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn
node browser/scripts/build-offline.mjs
cd ../..
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\backend\start_account_demo_lan.ps1 -Port 8020
```

Before starting, create `backend/.env` with `ACCOUNT_MAIL_MODE=resend`, your
`ACCOUNT_RESEND_API_KEY`, and an `ACCOUNT_MAIL_FROM` address on a Resend-verified
domain. The backend calls Resend over the internet while the phone communicates
with the backend over local Wi-Fi.

The script prints the exact phone URL, such as `http://192.168.9.3:8020`.
Open that address on a phone connected to the same Wi-Fi. Web automatically uses
the page's origin for the account API, so no phone-side backend setting is needed.
If Windows asks, allow Python on **Private networks**. LAN HTTP is sufficient to
create a local account and add a child, but mobile browsers can block camera
access on non-HTTPS pages.

For camera testing, use a debug Android build, which allows private-LAN HTTP:

```powershell
cd mobile/coaching
flutter build apk --debug --no-pub --dart-define=BACKEND_URL=http://192.168.9.3:8020
```

Replace the example address with the one printed by the LAN helper. Install
`build/app/outputs/flutter-apk/app-debug.apk` on the phone. Release builds still
require HTTPS.

To run the Mosque demo, use `.\backend\start_mosque_demo.ps1` from repository
root and set the app's backend address to `http://127.0.0.1:8011` on the host
(or the corresponding emulator/LAN address). This script enables the demo
explicitly; routes and notifications remain simulated.
[Full demo instructions](docs/MOSQUE_COMPANION.md).

Legacy prayer-analysis, live-streaming, reference-authoring and optional LLM
advisory APIs remain for compatibility/development. Default prayer screens do
not use them. See the [backend README](backend/README.md),
[legacy video API](docs/VIDEO_ANALYSIS.md) and
[reference authoring guide](docs/prayer-reference-admin.md). No provider key or
paid LLM request is needed for the local app or standard automated tests.

## Tests and current verification limits

After dependency setup and browser fixture generation:

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest -q
cd ../mobile/coaching
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
cd browser
npm.cmd test
```

Automated tests use synthetic fixtures/fake providers; they do not establish
real camera or general model accuracy. Separate model smoke/parity tools require
the bundled weights and export dependencies. Source-video acceptance fixtures,
logs, screenshots and reports under `output/` are local evidence excluded from
Git, so a fresh clone does not include those runs' raw artifacts.

Documented acceptance includes 100 real-image CPU parity cases on Samsung M52 /
Android 13, plus a subsequent 256-frame Fajr replay with optional normalization
and Ruku gating: 16/16 stations and 2/2 rakahs, still `REVIEW_REQUIRED` with
residual classifier errors. These are bounded results, not a claim of general
prayer accuracy. See [Android CPU acceptance](docs/ANDROID_LOCAL_PERFORMANCE.md)
and [quality options and phone replay](docs/LOCAL_QUALITY_OPTIONS.md).

Quality corrections are independent and off by default; the recommended preset
enables normalization and Ruku gating, retaining raw predictions and uncertainty.
Native iOS/desktop inference is unsupported. Physical live-camera, remaining
source-video and other-device acceptance are incomplete. Mosque Companion is a
demo; production routing/notifications are not implemented. Accounts require
configured email delivery and appropriate HTTPS/cookie/origin deployment.

The earlier geometry trainer and labelled synthetic simulation remain in source.
[Historical trainer documentation](docs/LEGACY_LOCAL_TRAINING.md) describes that
separate workflow. Current local architecture is in
[LOCAL_TRAINING.md](docs/LOCAL_TRAINING.md); newer account behavior is described
in [ACCOUNTS.md](docs/ACCOUNTS.md).
