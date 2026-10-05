#!/bin/bash
# Run as root after uploading immutable CI artifacts into /srv/iqtadi/incoming/ID.
set -Eeuo pipefail
release=${1:?release ID required}
target=${2:?web/backend/both required}
[[ "$release" =~ ^gha-[0-9]+-[0-9]+-[a-f0-9]{40}$ ]]
[[ "$target" == web || "$target" == backend || "$target" == both ]]
base=/srv/iqtadi
incoming="$base/incoming/$release"
next="$base/releases/$release"
backup="$base/backups/$release"
exec 9>"$base/deploy/deploy.lock"
flock -n 9 || { echo 'Another VPS deployment is running'; exit 1; }
[[ ! -e "$next" && ! -e "$backup" ]]
old_web=$(readlink -f "$base/current")
old_image=$(docker inspect --format '{{.Config.Image}}' iqtadi-backend)
candidate="iqtadi-check-$release"
web_changed=0
backend_stopped=0
backend_swapped=0
restore_link() {
    ln -sfn "$1" "$base/current-deploy-next"
    mv -Tf "$base/current-deploy-next" "$base/current"
}
wait_health() {
    for attempt in $(seq 1 90); do
        state=$(docker inspect --format '{{.State.Health.Status}}' "$1" 2>/dev/null || true)
        [[ "$state" != unhealthy ]] || return 1
        if [[ "$state" == healthy ]]; then return 0; fi
        sleep 2
    done
    return 1
}
rollback() {
    code=$?
    [[ "$code" != 0 ]] || code=1
    trap - ERR INT TERM
    set +e
    rollback_failed=0
    docker rm -f "$candidate" >/dev/null 2>&1
    if [[ "$web_changed" == 1 ]]; then restore_link "$old_web" || rollback_failed=1; fi
    if [[ "$backend_swapped" == 1 ]]; then
        # Retain failed-version data for inspection; restore the stopped-container snapshot.
        if ! (docker rm -f iqtadi-backend >/dev/null 2>&1 &&
            mv "$base/shared/data" "$backup/failed-data" &&
            cp -a "$backup/data" "$base/shared/data" &&
            bash "$incoming/backend/deploy/vps/run-backend.sh" "$old_image" &&
            wait_health iqtadi-backend); then rollback_failed=1; fi
    elif [[ "$backend_stopped" == 1 ]]; then
        docker start iqtadi-backend >/dev/null || rollback_failed=1
    fi
    if [[ "$rollback_failed" == 0 ]]; then
        echo 'Deployment failed; previous web/container/data restored.' >&2
    else
        echo "Deployment and rollback failed; inspect $backup before retrying." >&2
    fi
    exit "${code:-1}"
}
trap rollback ERR INT TERM
mkdir -p "$next" "$backup"
chmod 700 "$backup"
printf '%s\n' "$old_web" > "$backup/previous-web.txt"
printf '%s\n' "$old_image" > "$backup/previous-image.txt"
if [[ "$target" != backend ]]; then
    mkdir "$next/web"
    tar -xzf "$incoming/web.tar.gz" -C "$next/web" --no-same-owner
    chmod -R a+rX "$next/web"
    python3 "$incoming/verify-web.py" "$next/web"
    nginx -t
fi
if [[ "$target" != web ]]; then
    mkdir "$incoming/backend"
    tar -xzf "$incoming/backend.tar.gz" -C "$incoming/backend" --no-same-owner
    docker build -f "$incoming/backend/deploy/vps/Dockerfile" -t "iqtadi-backend:$release" "$incoming/backend"
    install -d -m 700 -o 10001 -g 10001 "$incoming/check-data"
    # Preflight startup on isolated data, never against the live SQLite databases.
    docker run -d --name "$candidate" --network none \
        --env-file "$base/shared/backend.env" \
        -v "$incoming/check-data:/app/data" "iqtadi-backend:$release" >/dev/null
    wait_health "$candidate"
    docker rm -f "$candidate" >/dev/null
    docker stop iqtadi-backend >/dev/null
    backend_stopped=1
    # No live SQLite file copying: the current container is stopped for the snapshot.
    cp -a "$base/shared/data" "$backup/data"
    docker rm iqtadi-backend >/dev/null
    backend_swapped=1
    bash "$incoming/backend/deploy/vps/run-backend.sh" "iqtadi-backend:$release"
    wait_health iqtadi-backend
fi
if [[ "$target" != backend ]]; then
    web_changed=1
    restore_link "$next"
fi
url=$(cat "$base/deploy/public-url.txt")
[[ "$url" == https://vps-c79afd97.vps.ovh.ca ]]
[[ "$(curl --fail --silent --show-error --max-time 30 "$url/healthz")" == *'"status":"ok"'* ]]
if [[ "$target" != backend ]]; then
    curl --fail --silent --show-error --max-time 30 "$url/iqtadi-offline-manifest.json" > "$incoming/published-manifest.json"
    cmp "$next/web/iqtadi-offline-manifest.json" "$incoming/published-manifest.json"
    curl --fail --silent --show-error --max-time 30 "$url/recognizer/bridge.js" >/dev/null
fi
[[ "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 "$url/admin")" == 404 ]]
printf '%s\n' "$release $target" > "$base/deploy/last-deployment.txt"
trap - ERR INT TERM
echo "Deployed $target: $release"
echo "Previous web/image and backend data snapshot (if applicable): $backup"
