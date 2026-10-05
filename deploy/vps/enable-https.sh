#!/bin/bash
set -euo pipefail
mkdir -p /srv/iqtadi/acme
cp /srv/iqtadi/deploy/nginx-http.conf /etc/nginx/sites-available/iqtadi-public
ln -sfn /etc/nginx/sites-available/iqtadi-public /etc/nginx/sites-enabled/iqtadi-public
nginx -t
systemctl reload nginx
certbot certonly --webroot -w /srv/iqtadi/acme -d vps-c79afd97.vps.ovh.ca --non-interactive --agree-tos --register-unsafely-without-email
cp /srv/iqtadi/deploy/nginx-https.conf /etc/nginx/sites-available/iqtadi-public
nginx -t
systemctl reload nginx
install -d /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\n/usr/sbin/nginx -t && /usr/bin/systemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/iqtadi-nginx
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/iqtadi-nginx
systemctl enable --now certbot.timer
systemctl disable --now iqtadi-tunnel
python3 - <<'PY'
import json,pathlib
url='https://vps-c79afd97.vps.ovh.ca'
p=pathlib.Path('/srv/iqtadi/shared/backend.env')
lines=[s for s in p.read_text().splitlines() if not s.startswith(('ACCOUNT_PUBLIC_URL=','ACCOUNT_ALLOWED_ORIGINS='))]
lines+=['ACCOUNT_PUBLIC_URL='+url,'ACCOUNT_ALLOWED_ORIGINS='+json.dumps([url])]
p.write_text('\n'.join(lines)+'\n');p.chmod(0o600)
pathlib.Path('/srv/iqtadi/deploy/public-url.txt').write_text(url+'\n')
PY
image=$(docker inspect --format '{{.Config.Image}}' iqtadi-backend)
docker stop iqtadi-backend >/dev/null
docker rm iqtadi-backend >/dev/null
bash /srv/iqtadi/deploy/run-backend.sh "$image"
