# Temporary Cloudflare test connection

The tunnel runs the existing FastAPI app through a small public gateway. Analysis,
reference download, guidance, job tokens, evidence and deletion use the original
handlers. No model settings or analysis behavior changes. Admin editing and API
documentation stay outside the public gateway.

1. Install the official connector if it is not already in `backend/tools/cloudflared.exe`:
   `winget install --id Cloudflare.cloudflared --exact`.
2. Stop the usual backend on port 8000. From the repository root run:
   `powershell -ExecutionPolicy Bypass -File backend/start_cloudflare.ps1`.
3. Copy the `https://...trycloudflare.com` URL printed by cloudflared.
4. In the app, open the home screen side menu, enter the root HTTPS URL under
   **رابط API**, then tap **حفظ الرابط**. Open a prayer to start a new analysis.
5. Keep the command running during testing. Ctrl+C closes the connector and its
   backend. Each new tunnel can have a different URL; update the app setting.

The device remembers the URL across restarts. **استعادة الرابط الافتراضي** restores
the build's `BACKEND_URL` (or localhost). Existing sessions keep their original
backend address. Enter the root URL without `/api`, credentials, query or fragment.

Use `/healthz` and `/api/v1/prayer-analyses/config` to check the tunnel. `/admin/prayer`
must return 404 publicly. Use the normal `backend/start_backend.bat` for local admin
editing when the test tunnel is stopped. The launcher deliberately fails if its
port is in use; restarting the backend ends its in-memory analysis jobs.

Quick Tunnels are for testing and have no uptime guarantee. They allow at most
200 in-flight requests and do not support SSE; this app uses HTTP polling.
The URL is publicly reachable; existing per-job bearer protection remains in place.
Avoid using real private recordings when sharing the test address.

Official instructions: https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
