# VPS deployment

Deployed on 2026-10-05 through the SSH alias `iqtadi-vps`. Manual GitHub Actions deployment is available. This is a testing deployment with the stable URL https://vps-c79afd97.vps.ovh.ca.

## Agent entry point and preferred deployment

When asked to deploy, use direct SSH deployment from the local machine by default.
Do not wait for GitHub Actions unless the user explicitly requests it. GitHub push
and server deployment are separate operations. Only push files within the requested
scope; existing unrelated working-tree changes must not enter the commit/artifact.
This document is the deployment runbook for any AI agent working in this repository.

## Direct deployment from Windows (validated 2026-10-06)

Run commands from the repository root in PowerShell. SSH alias `iqtadi-vps` currently
uses `ubuntu@148.113.252.100` and the configured local SSH key. Other agents/machines
must have authorized SSH access and verified host keys; do not copy private keys into
the repository or disable host-key checks. The deployment user needs `sudo -n`.

1. Inspect `git status --short` and the diff. Commit the intended code before
   packaging so the release records its source revision. Check SSH and current state:

```powershell
ssh -o BatchMode=yes -o ConnectTimeout=15 iqtadi-vps "readlink /srv/iqtadi/current; cat /srv/iqtadi/deploy/last-deployment.txt"
```

2. Validate changed code, then build the complete Web distribution:

```powershell
Push-Location mobile/coaching
try {
    flutter analyze --no-pub
    # The six known informational lints are documented below; inspect new findings.
    flutter test --no-pub test/live_analysis_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
} finally { Pop-Location }
& ./deploy/vps/build-web.ps1
if ($LASTEXITCODE -ne 0) { throw 'Web build failed' }
```

Choose additional focused tests according to the changed feature. The build script
runs browser build, Flutter Release Web and offline packaging. Never upload a partial
`build/web` or edit its files after generating the offline manifest without regenerating it.

3. Package and upload. `deploy-release.sh` currently requires release IDs matching
   `gha-NUMBER-NUMBER-FULLCOMMIT`; direct deployments use a UTC numeric timestamp
   and attempt `1` within that format. This prefix is a parser constraint, not evidence
   that a GitHub Actions run exists. Do not reuse a release ID.

```powershell
$sourceCommit = (git rev-parse HEAD).Trim()
$deploymentStamp = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
$releaseId = "gha-$deploymentStamp-1-$sourceCommit"
$remoteDir = "/srv/iqtadi/incoming/$releaseId"
$stagingDir = Join-Path (Get-Location) 'output/direct-deploy'
New-Item -ItemType Directory -Force $stagingDir | Out-Null
# Bash scripts uploaded from Windows must use LF, without a UTF-8 BOM.
$utf8NoBom = [Text.UTF8Encoding]::new($false)
foreach ($scriptName in @('deploy-release.sh', 'verify-web.py')) {
    $scriptText = [IO.File]::ReadAllText((Join-Path (Get-Location) "deploy/vps/$scriptName"))
    [IO.File]::WriteAllText((Join-Path $stagingDir $scriptName), $scriptText.Replace("`r`n", "`n"), $utf8NoBom)
}
tar -czf "$stagingDir/web.tar.gz" -C mobile/coaching/build/web .
if ($LASTEXITCODE -ne 0) { throw 'Packaging failed' }
ssh -o BatchMode=yes iqtadi-vps "sudo -n mkdir -p '$remoteDir' && sudo -n chown ubuntu:ubuntu '$remoteDir'"
if ($LASTEXITCODE -ne 0) { throw 'Remote preparation failed' }
scp -o BatchMode=yes "$stagingDir/web.tar.gz" "$stagingDir/deploy-release.sh" "$stagingDir/verify-web.py" "iqtadi-vps:$remoteDir/"
if ($LASTEXITCODE -ne 0) { throw 'Upload failed' }
ssh -o BatchMode=yes -o ServerAliveInterval=15 iqtadi-vps "sudo -n bash '$remoteDir/deploy-release.sh' '$releaseId' web"
if ($LASTEXITCODE -ne 0) { throw 'Deployment failed; inspect rollback output' }
```

This verifies every static file hash, tests Nginx, atomically changes `current`, and
checks public health/manifest/bridge/admin blocking. It retains the previous release
and attempts rollback on failure. Web-only deployment leaves the backend running.
Never use initial provisioning (`prepare-server.sh`) to update an existing server.
Avoid simultaneous direct/Actions deployments; the server script also enforces a lock.

4. Verify externally and retain output:

```powershell
$publishedManifest = Invoke-RestMethod 'https://vps-c79afd97.vps.ovh.ca/iqtadi-offline-manifest.json'
$localManifest = Get-Content mobile/coaching/build/web/iqtadi-offline-manifest.json -Raw | ConvertFrom-Json
if ($publishedManifest.version -ne $localManifest.version) { throw 'Published version mismatch' }
Invoke-RestMethod 'https://vps-c79afd97.vps.ovh.ca/healthz' | ConvertTo-Json
ssh iqtadi-vps "readlink /srv/iqtadi/current; cat /srv/iqtadi/deploy/last-deployment.txt"
```

For UI/runtime acceptance also run the existing `browser/scripts/verify-vps.mjs`
workflow as appropriate, or inspect the changed screen in a real browser. A successful
build/hash check is not physical-camera or user-browser cache acceptance. Existing
clients may need refresh or the explicit "تطبيق التحديث" action.

For backend or combined updates, additionally package the exact backend whitelist
shown in `.github/workflows/deploy-vps.yml` as `backend.tar.gz` into the same incoming
directory, then invoke the script with `backend` or `both`. Do not upload `.env`,
personal media, or `backend/data`. Backend deployment builds/tests a candidate image,
stops the old container for a consistent snapshot and swaps it using existing server
configuration; a brief interruption occurs. Use only when backend changes are requested.

## Server and browser logs (verified 2026-10-06)

| Source | Location/access | What it records |
|---|---|---|
| Nginx requests | `/var/log/nginx/access.log` | Web assets and proxied API HTTP requests/status codes |
| Nginx errors | `/var/log/nginx/error.log` | HTTP serving/proxy errors |
| Backend | `sudo docker logs iqtadi-backend` | stdout/stderr, startup and application errors |
| Service events | `journalctl -u nginx` | Nginx service lifecycle/errors |
| Last deployment | `/srv/iqtadi/deploy/last-deployment.txt` | Latest successful release ID and target, not a complete transcript |
| Deployment artifacts | `/srv/iqtadi/incoming/<ID>/`, `/srv/iqtadi/backups/<ID>/` | Artifacts, published manifest and rollback metadata, not a full log stream |

```powershell
ssh iqtadi-vps "sudo -n tail -n 100 /var/log/nginx/access.log"
ssh iqtadi-vps "sudo -n tail -n 100 /var/log/nginx/error.log"
ssh iqtadi-vps "sudo -n docker logs --timestamps --since 1h --tail 200 iqtadi-backend 2>&1"
ssh iqtadi-vps "sudo -n journalctl -u nginx --since '1 hour ago' --no-pager"
# Follow live backend messages (Ctrl+C stops viewing, not the service):
ssh iqtadi-vps "sudo -n docker logs -f --tail 50 iqtadi-backend"
# Resolve the current container log path and rotation configuration dynamically:
ssh iqtadi-vps "sudo -n docker inspect --format '{{.LogPath}} {{json .HostConfig.LogConfig}}' iqtadi-backend"
```

The current Docker driver is `json-file`; its internal path under
`/var/lib/docker/containers/<container-id>/` changes on container recreation. Prefer
`docker logs` to editing/reading the underlying JSON directly. `run-backend.sh`
configures rotation to three files of 10 MB each; these are bounded operational logs,
not a permanent archive. Application logging targets stdout and suppresses normal
Uvicorn access messages below WARNING; use Nginx access logs for request history.
Nginx logs inherit the global paths and may contain other configured sites; inspect
current configuration/rotation rather than assuming a dedicated application log.

Chrome JavaScript, service-worker download/cache/quota errors and local inference
are not automatically sent to the server. Nginx can show a failed HTTP asset request,
but cannot explain a client-side cache/hash/quota failure after a successful response.
In the affected Chrome session open DevTools > Console and Application > Service
Workers / Cache Storage. `window.iqtadiOffline.status()` returns the actual offline
state and warning; preserve that output before clearing cache or unregistering workers.
Do not infer the cause of an offline banner from its generic text alone.

## Layout and access

- `/srv/iqtadi/current/web`: complete Flutter Release Web distribution; current points
  to the last successful release. Read `readlink /srv/iqtadi/current` for live state;
  `first` retains the initial release.
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
