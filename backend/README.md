# Iqtadi backend

FastAPI server for optional accounts/family/classroom monitoring, the simulated
Mosque Companion, and retained prayer-analysis/reference/guidance development APIs.
The default Flutter prayer flows run inference, reports, references and Arabic cues
on-device and do not require this server. Accounts receive only final scalar results;
they do not receive frames, landmarks or model tensors.

Legacy server inference uses the included `models/prayer_action/` bundle (metadata,
normalization, MediaPipe task and three TorchScript weights). No UI folder is required
for that server runtime. Python is also used at build time to export/validate browser
models; see the [root setup instructions](../README.md).

Run all commands from this directory:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item ../.env.example .env
# Edit .env for the connected features you intend to use.
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Use Python 3.11 for the documented Windows build/export workflow. Create `.env`
only on initial setup; preserve an existing file and keep secrets out of Git.
Health check: `http://127.0.0.1:8000/healthz`.

For retained real server-analysis tooling, these settings select the model bundle:

```dotenv
INFERENCE_PROVIDER=real
ANALYSIS_ALLOW_MOCK=false
PRAYER_MODEL_BUNDLE_DIR=models/prayer_action
```

Verify weights locally with `.\.venv\Scripts\python.exe tools/smoke_prayer_model.py`.
Build a standalone image from this directory with `docker build -t iqtadi-backend .`.
Pass environment settings when starting the image; Docker includes model weights.
Alternatively run `docker compose up --build` from repository root after configuring
`backend/.env`. Docker runs the server; it does not build/host the Flutter app.

On Windows, `start_backend.bat` selects this directory and its Python explicitly.
After moving a virtual environment, reactivate it and use `python -m uvicorn`;
existing terminal PATH values and old executable launchers can still select the old project.

## Accounts, monitoring and Mosque Companion

Accounts expose `/api/v1/accounts`, with backend-owned password hashing, email
verification, guardian sessions, child pairing and scalar-result synchronization.
Configure `ACCOUNT_PUBLIC_URL`, exact `ACCOUNT_ALLOWED_ORIGINS`, Resend or SMTP
settings, and `ACCOUNT_DB` using `.env.example`. Real Resend delivery needs
`ACCOUNT_RESEND_API_KEY` and a verified-domain `ACCOUNT_MAIL_FROM`. Explicit
`ACCOUNT_MAIL_MODE=development` writes private `.eml` files to
`ACCOUNT_MAIL_OUTBOX`, never bypasses verification, and does not send real mail.
Do not serve that directory publicly.

Web accounts use HttpOnly cookies; prefer Web/API on the same HTTPS origin through
a reverse proxy. `ACCOUNT_SECURE_COOKIES=false` is for explicit local HTTP testing
only. Android uses secure token storage and the app's configured backend address.
See [accounts setup and limits](../docs/ACCOUNTS.md).

Mosque Companion remains an explicitly simulated demo with no real notifications
or production street routing. `MOSQUE_DEMO_ENABLED` defaults to false. From the
repository root, `.\backend\start_mosque_demo.ps1` enables it on port 8011; configure
the app's server URL accordingly. See [demo instructions](../docs/MOSQUE_COMPANION.md).
For the normal port 8000 server, enabling it in `.env` requires restarting the server.

On an Android emulator use `http://10.0.2.2:8000`; on a physical phone use the
computer's reachable LAN address or an HTTPS server. The phone's `127.0.0.1` is not
the development computer. Account URL changes require restarting the app/controller.

## Tests and retained API boundaries

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

Standard tests use synthetic data/fake providers and do not require paid services
or a camera. Real model smoke/parity tools require weights. Existing single-process
analysis jobs, admin reference tools and optional LLM guidance remain development
compatibility paths. Default Flutter inference never uploads media to these APIs.
For their lifecycle/security requirements see [video API](../docs/VIDEO_ANALYSIS.md)
and [admin authoring](../docs/prayer-reference-admin.md). Public deployment needs
appropriate HTTPS, authentication, rate limits and CORS; account authentication
does not automatically protect the separate legacy admin/analysis routes.

Source-video reports and acceptance artifacts under `../output/` are local and
excluded from Git. Documented Android acceptance is summarized in the root README;
automated server tests do not establish general classifier or device accuracy.

## Optional experimental postprocessing

These four settings apply to retained backend analysis and are OFF by default.
Flutter local analysis has its own independent options; changing `.env` does not
change those client options. See [local quality switches](../docs/LOCAL_QUALITY_OPTIONS.md).
Set any option to `true` independently in `backend/.env`, then restart the backend:

```dotenv
PRAYER_MIRROR_SUJOOD_RECOVERY=false
PRAYER_RUKU_GEOMETRY_GATE=false
PRAYER_SEATED_PROBABILITY_PROJECTION=false
PRAYER_SEQUENCE_NORMALIZATION=false
```

The first three govern mirrored Sujud recovery, the straight-knee Ruku gate and seated probability aggregation.
The fourth governs trimming, transitional takbir filtering, same-posture consolidation and tolerance of uncertain transition samples.
With all disabled, original model labels/confidence are preserved (apart from the existing canonical label mapping),
and strict conservative alignment handles the report. Recorded demo still includes final sitting and salam as requested.
The earlier supplied-video evaluation used opt-in corrections; it does not describe default raw mode.
The public `/api/v1/prayer-analyses/config` exposes active switches under `experimental_postprocessing`.
Tests cover defaults, disabled behavior and opt-in behavior; that is separate from real-video accuracy acceptance.
