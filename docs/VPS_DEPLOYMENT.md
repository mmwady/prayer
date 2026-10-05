# VPS deployment

Deployed on 2026-10-05 through the SSH alias `iqtadi-vps`. GitHub deployment automation
is intentionally deferred. This is a testing deployment with the stable URL https://vps-c79afd97.vps.ovh.ca.

## Layout and access

- `/srv/iqtadi/current/web`: complete Flutter Release Web distribution; current points
  to `/srv/iqtadi/releases/20261005-model-progress-final`; `first` retains the initial release.
- `/srv/iqtadi/shared/data`: persistent SQLite/reference/analysis data, mounted at
  `/app/data` in the backend container, owned by UID 10001.
- `/srv/iqtadi/shared/backend.env`: server-only configuration, mode 0600. No local
  developer secrets or personal media/database files were uploaded.
- `/srv/iqtadi/deploy`: installed deployment scripts and `public-url.txt`.
- Docker image `iqtadi-backend:20261005-test`: Python 3.11 and CPU-only Torch 2.5.1.
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
Secure/HttpOnly/SameSite strict, allowed origins are limited to the stable HTTPS URL. SMTP is
unconfigured: ordinary signup email verification/password-reset delivery is unavailable
until actual SMTP settings are provided. Development email mode was not enabled.

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
is not a general update/rollback command. GitHub automation will implement later release
creation, verification, activation and rollback.

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
