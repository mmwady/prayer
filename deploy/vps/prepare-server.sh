#!/bin/bash
set -euo pipefail
cd /srv/iqtadi/releases
mkdir -p first
tar -xzf backend-source.tar.gz -C first
cp first/deploy/vps/* /srv/iqtadi/deploy/
chmod 755 /srv/iqtadi/deploy/*.sh
install -m 644 /srv/iqtadi/deploy/nginx.conf /etc/nginx/sites-available/iqtadi
ln -sfn /etc/nginx/sites-available/iqtadi /etc/nginx/sites-enabled/iqtadi
nginx -t
systemctl reload nginx
mkdir -p /srv/iqtadi/shared/data
chown 10001:10001 /srv/iqtadi/shared/data
chmod 700 /srv/iqtadi/shared/data
if [ ! -f /srv/iqtadi/shared/backend.env ]; then
    umask 077
    cat > /srv/iqtadi/shared/backend.env <<'ENV'
LOG_LEVEL=INFO
PRAYER_GUIDANCE_ENABLED=false
MOSQUE_DEMO_ENABLED=true
ACCOUNT_MAIL_MODE=smtp
ACCOUNT_SECURE_COOKIES=true
INFERENCE_PROVIDER=real
ANALYSIS_ALLOW_MOCK=false
PRAYER_MODEL_BUNDLE_DIR=models/prayer_action
ENV
    printf 'PRAYER_ADMIN_TOKEN=%s\n' "$(openssl rand -hex 32)" >> /srv/iqtadi/shared/backend.env
fi
install -m 644 /srv/iqtadi/deploy/iqtadi-tunnel.service /etc/systemd/system/iqtadi-tunnel.service
systemctl daemon-reload
systemctl enable --now iqtadi-tunnel
cat /srv/iqtadi/deploy/public-url.txt
cd /srv/iqtadi/releases/first
docker build -f deploy/vps/Dockerfile -t iqtadi-backend:20261005-test .
bash /srv/iqtadi/deploy/run-backend.sh iqtadi-backend:20261005-test
