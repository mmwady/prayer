#!/bin/bash
set -euo pipefail
docker run -d --name iqtadi-backend --restart unless-stopped \
    --env-file /srv/iqtadi/shared/backend.env \
    -p 127.0.0.1:8000:8000 \
    -v /srv/iqtadi/shared/data:/app/data \
    --log-opt max-size=10m --log-opt max-file=3 \
    "$1"
