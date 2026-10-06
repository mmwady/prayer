# VPS deployment

Deployed on 2026-10-05 through the SSH alias `iqtadi-vps`. Manual GitHub Actions deployment is available. This is a testing deployment with the stable URL https://vps-c79afd97.vps.ovh.ca.

## Current update: 2026-10-06

The user separately authorized direct deployment of review commit `51efdb6` and
the Gmail SMTP credential transfer after its initial automatic approval rejection.
Web/backend release:
`gha-20261006063004-1-51efdb64fac025180df82752338a9aa3bd508552`.
No main merge/push was performed; the inherited main Git validation gate remains
closed. This was direct SSH activation, not a GitHub Actions run.

- Candidate Docker startup, isolated schema-v4/foreign-key check and three Linux
  release/rollback tests passed. Installed runtime dependencies pass `pip check`.
- Web packaging and server verification passed for all **80 files**, 126,913,014
  bytes, offline version `986a399e1fb6ad2093576031`. All 141 protected prayer blobs
  and Web/APK model manifest hashes still match Wady.
- Stopped-container data snapshot and original env were retained under
  `/srv/iqtadi/backups/gha-20261006063004-1-51efdb64fac025180df82752338a9aa3bd508552/`
  (directory mode 0700). Activation's temporary release script restores both data
  and env if cutover fails; neither database reset nor fixture database upload occurred.
- Only SMTP and account-origin settings were transmitted via encrypted SSH stdin.
  Server `backend.env` is root-owned mode 0600; no API key/password is in source,
  Web assets, reports or GitHub. Gmail implicit SSL on port 465 authenticated from
  the VPS before cutover. Paid guidance remains disabled.
- Public health and account config pass (`email_configured=true`, mode SMTP).
  Real published Flutter signup sent a received Gmail message; its production
  link was confirmed in Chrome, followed by verified login/cookie reload. Account
  and SELF ownership, token reuse rejection, payload scrubbing and schema-v4
  integrity passed. The real user account remains; live Resend/password-reset
  delivery and physical device acceptance remain unverified.
- Public Chrome regression passed six prayer routes, a real 16-frame local video
  using all three models (`REVIEW_REQUIRED` preserved), and simulated live-camera
  input with 15 processed frames/one captured action. No prayer images/model inputs
  were posted to the backend. Admin/OpenAPI and missing model/WASM 404 checks and
  rejection of an unauthorized account Origin passed; no page JavaScript exceptions.
  Captured console output contains the ONNX "Unknown CPU vendor" warning and the
  TensorFlow Lite XNNPACK startup info; both inference workflows still passed.

Evidence under ignored `output/deployment/`, `output/vps-mail-live/` and
`output/vps/`; prior release/data/env remain available for operator rollback.
See [mail delivery checks](ACCOUNT_EMAIL_DELIVERY.md) for exact test boundaries.

## Layout and access

- `/srv/iqtadi/current/web`: complete Flutter Release Web distribution; current points
  to `/srv/iqtadi/releases/gha-20261006063004-1-51efdb64fac025180df82752338a9aa3bd508552`;
  previous releases and `first` are retained.
- `/srv/iqtadi/shared/data`: persistent SQLite/reference/analysis data, mounted at
  `/app/data` in the backend container, owned by UID 10001.
- `/srv/iqtadi/shared/backend.env`: server-only configuration, mode 0600. The
  explicitly approved Gmail SMTP credential is installed; no other local developer
  secrets or personal media/database files were uploaded.
- `/srv/iqtadi/deploy`: installed deployment scripts and `public-url.txt`.
- Docker image `iqtadi-backend:gha-20261006063004-1-51efdb64fac025180df82752338a9aa3bd508552`:
  Python 3.11 and CPU-only Torch 2.5.1.
  Container `iqtadi-backend` has `unless-stopped` restart policy and a health check.
- Public Nginx listens on IPv4/IPv6 ports 80 and 443 for `vps-c79afd97.vps.ovh.ca`.
  HTTP redirects to HTTPS except the ACME webroot `/srv/iqtadi/acme`.
  The existing default port-80 site remains unchanged. Backend binds only to
  **127.0.0.1:8000**; the former application loopback listener remains on port 8080.
- Let’s Encrypt certificate: `/etc/letsencrypt/live/vps-c79afd97.vps.ovh.ca/`;
  initial expiry 2027-01-03. `certbot.timer` renews automatically and the deploy hook
  checks/reloads Nginx. Certificate registration used no email contact.
- `iqtadi-tunnel.service` is stopped and disabled to avoid replacing the stable
  account origin. `/srv/iqtadi/deploy/public-url.txt` holds the stable HTTPS URL.
- `/api/` preserves backend paths; `/healthz` is proxied separately. Administration,
  docs and OpenAPI are blocked; missing model/WASM paths return 404.
- `deploy/vps/nginx-http.conf`, `nginx-https.conf` and `enable-https.sh` describe
  activation. Web uses its own origin without rebuilding; backend account public URL
  and allowed origins now contain only the stable HTTPS hostname.
- Browser storage from the previous temporary hostname does not migrate automatically.

## Enabled features and limits

Prayer video/image/live inference runs locally with the original three packaged models.
The complete offline distribution contains 80 files / approximately 127 MB. Initial
downloads may take time. Real physical camera/mobile-browser acceptance still needs
a device test; the deployment browser check uses a simulated canvas camera and real inference.

Mosque Companion is enabled **as a simulated demo**. Paid guidance calls are disabled
(`PRAYER_GUIDANCE_ENABLED=false`); no provider key was installed. Account cookies are
Secure/HttpOnly/SameSite strict, allowed origins are limited to the stable HTTPS URL.
Gmail SMTP is configured and real signup/verification delivery passed. Password
reset uses the same transport but live reset delivery was not exercised in this
deployment. Development email mode is not enabled.

## Operations

```powershell
ssh iqtadi-vps "sudo docker ps; sudo systemctl status nginx certbot.timer --no-pager"
ssh iqtadi-vps "sudo docker logs --tail 50 iqtadi-backend"
ssh iqtadi-vps "sudo certbot renew --dry-run --run-deploy-hooks --no-random-sleep-on-renew"
ssh iqtadi-vps "sudo docker restart iqtadi-backend"
```

Backend restart preserves stored account/Mosque data but loses in-memory legacy
analysis sessions. The public hostname stays the same across application/service restarts.
Restarting a container does not reload its env-file; apply account/SMTP changes by
recreating it using `/srv/iqtadi/deploy/run-backend.sh` with its current image.
Back up SQLite using its backup API before migrations; retain `/srv/iqtadi/shared`
when replacing releases. Do not copy live SQLite files while writes are in progress.

## Rebuild and verification

From `mobile/coaching/browser`, run `npm.cmd run build`. From `mobile/coaching`:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/backend_settings_test.dart
flutter build web --release --no-pub --pwa-strategy=none --no-web-resources-cdn
node browser/scripts/build-offline.mjs
node browser/scripts/verify-vps.mjs https://vps-c79afd97.vps.ovh.ca
```

For the deployed fallback-font packaging, replace the standalone offline-generator
step with `../../deploy/vps/package-web.ps1`. It includes the exact Roboto WOFF2
fallback requested by this Flutter SDK and then generates the offline manifest.
`deploy/vps/build-web.ps1` runs browser build, Flutter build and this packaging;
run the analyzer/tests separately before publishing. Dependency versions resolved
for the initial backend image are saved on the server in
`/srv/iqtadi/deploy/requirements-resolved.txt`.

Use the complete `build/web` directory, regenerate the offline manifest after building,
and deploy a new release directory atomically. Backend build context must contain
`backend/app`, `backend/models`, `backend/pyproject.toml`, `backend/README.md` and
`deploy/vps/Dockerfile`; do not include `.env` or `backend/data`. Server provisioning
scripts under `deploy/vps` describe the **initial** installation; `prepare-server.sh`
is not a general update/rollback command. The manual GitHub workflow implements release creation, verification, activation and rollback.

Public browser evidence is written under `output/vps` (git-ignored). It covers the six
prayer routes, a real 16-frame local video, three-model results, simulated live-camera
capture/report, no prayer network payload, API origins, health, blocked administration
and missing model paths. `verify-backend.py` creates/removes a synthetic smoke account,
verifies real HTTPS cookies and checks its SQLite session after container restart.
No email or paid service call is made.

## Verified deployment acceptance (2026-10-05)

- `flutter analyze --no-pub`: six existing informational findings, no errors/warnings.
- Four backend-address Flutter tests passed; Flutter Release Web build passed.
- Server static hash verification passed for all 80 files (126,799,138 bytes),
  offline version `375cd4fb2d9900a80d25d511`.
- Public Chrome acceptance passed: six prayer routes, 16 real video frames with
  three individual model results each, locally persisted report (`REVIEW_REQUIRED`),
  simulated live camera with 23 processed frames / one automatic capture, local
  report saving and zero prayer image/video HTTP payloads. No page JavaScript exceptions.
- Public account origin/config and blocked administration/missing assets passed;
  signup mail availability correctly returned false. Account screen rendered.
- Synthetic real HTTPS login cookie passed Secure/HttpOnly/SameSite/path checks;
  its SQLite-backed session survived backend container restart; test account removed.
- Public Mosque demo session creation and actor-state retrieval passed. All
  notifications/routing remain simulated. Docker dependency check passed.
- Services are enabled at boot; an actual full VPS reboot and physical camera/device
  acceptance were not performed. The current public URL is read from `public-url.txt`.

## Stable HTTPS activation (2026-10-05)

- OVH hostname certificate issued successfully; external HTTP redirects and trusted
  HTTPS returned 301/200. IPv6 HTTPS health check passed.
- Certbot simulated renewal and Nginx deploy hook passed; timer enabled.
- Backend healthy; real synthetic HTTPS login and secure cookie checks passed;
  session survived container restart and synthetic account was removed.
- Stable-origin Chrome acceptance now passes after the model preparation fix:
  local file opening finishes independently, model download percentage/bytes are visible,
  worker inference completes without a timed fallback, and the pose model downloads once.
  Real video: 16 frames / three-model predictions / local REVIEW_REQUIRED report.
  Simulated camera with real inference: 24 frames / one capture / saved report.
  Physical camera remains unverified. Tests use a cold browser with service workers
  blocked and a 1 MiB/s network limit only inside the automated online check.
- File hashes/model weights are unchanged. The pipeline signature/model version was
  refreshed to match the changed initialization source. Runtime asset hash verification
  and inference preprocessing/class/ensemble rules remain intact.
- Validation: 30 focused Flutter tests and seven asset/initialization/progress tests passed;
  analyzer reports only the six pre-existing informational findings. Release build passed.
- Existing offline users can use "تطبيق التحديث" when the app reports an available update;
  otherwise close/reopen or refresh the page. First model downloads still depend on network
  speed; download progress is per file, not an estimate of the entire initialization time.

## Manual GitHub Actions deployment

Open GitHub Actions -> Deploy Iqtadi to VPS -> Run workflow, select main and:
- web: Flutter Web only (default); backend/data are left running.
- backend: Docker backend only; current Web remains active.
- both: build/validate both, then activate together with rollback on failed smoke checks.

This workflow has only workflow_dispatch; pushing a commit does not deploy.
It uses VPS_HOST, VPS_USER, VPS_PORT, VPS_SSH_KEY and VPS_KNOWN_HOSTS repository
secrets. The SSH key must be unencrypted and the server user must support sudo -n.
Host-key checking is mandatory. No secret files or personal databases are uploaded.
Flutter 3.41.2/Node 24 builds match the validated app runtime. JSON model asset bytes
are preserved by .gitattributes so Windows/Linux checkout cannot invalidate hashes.

Each run uploads to /srv/iqtadi/incoming/gha-RUN-ATTEMPT-COMMIT, verifies all Web
hashes, and activates /srv/iqtadi/releases/ID with an atomic current symlink switch.
Backend updates build on the VPS, test startup with isolated empty data, stop the old
container for a consistent data snapshot, and reuse the existing environment/data mount.
A brief backend interruption occurs during this swap. Failed public health, manifest
or administration checks trigger restoration of previous Web/image/data. Rollback
failures are reported explicitly. Snapshots/releases are retained; no automated pruning.
The selected commit/target appear in the workflow summary and last-deployment.txt.

Three isolated deployment tests exercise web-only activation, combined-release rollback
and rejection of invalid static hashes. These test the script with simulated Docker/HTTP;
they do not claim a real production failure was injected.
