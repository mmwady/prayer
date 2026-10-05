#!/bin/bash
set -euo pipefail
for attempt in $(seq 1 120); do
    url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /var/log/iqtadi-tunnel.log | head -n 1 || true)
    if [ -n "$url" ]; then
        python3 - "$url" <<'PY'
import json, pathlib, sys
url = sys.argv[1]
path = pathlib.Path('/srv/iqtadi/shared/backend.env')
if path.exists():
    lines = [s for s in path.read_text().splitlines() if not s.startswith(('ACCOUNT_PUBLIC_URL=', 'ACCOUNT_ALLOWED_ORIGINS='))]
    lines += ['ACCOUNT_PUBLIC_URL=' + url, 'ACCOUNT_ALLOWED_ORIGINS=' + json.dumps([url])]
    path.write_text('\n'.join(lines) + '\n')
    path.chmod(0o600)
pathlib.Path('/srv/iqtadi/deploy/public-url.txt').write_text(url + '\n')
PY
        if docker container inspect iqtadi-backend >/dev/null 2>&1; then
            # Restarting does not reload --env-file: recreate with the new URL.
            image=$(docker inspect --format '{{.Config.Image}}' iqtadi-backend)
            docker stop iqtadi-backend >/dev/null
            docker rm iqtadi-backend >/dev/null
            bash /srv/iqtadi/deploy/run-backend.sh "$image"
        fi
        exit 0
    fi
    sleep 1
done
echo 'Temporary HTTPS URL was not received' >&2
exit 1
