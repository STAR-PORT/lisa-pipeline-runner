#!/usr/bin/env bash
set -euo pipefail

# Customizable environment variables:
#   HPC_PROJECT_ROOT  - base project path (default: /projects/EEHPC-DEV-2026D02-075)
#   TOOLS_DIR         - tool install path (default: ${HPC_PROJECT_ROOT}/tools)
#   CACHE_DIR         - local cache root (default: ${HPC_PROJECT_ROOT}/cache)
#   SYNC_DIR          - sync script directory (default: ${HPC_PROJECT_ROOT}/sync)
#   INTERLINK_DIR     - InterLink state directory (default: ${HPC_PROJECT_ROOT}/.interlink)
#   MINIO_ACCESS_KEY  - MinIO access key (default: admin)
#   MINIO_SECRET_KEY  - MinIO secret key (default: admin123)
#   MINIO_HOST        - MinIO host (default: 68.221.216.246)
#   MINIO_PORT        - MinIO port (default: 9000)
#   MINIO_SCHEME      - MinIO scheme (default: http)
#   MINIO_ALIAS       - MinIO alias name (default: myminio)
#   MINIO_REMOTE_ROOT - remote sync root (default: ${MINIO_ALIAS}/results)

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/EEHPC-DEV-2026D02-075}"
TOOLS_DIR="${TOOLS_DIR:-${HPC_PROJECT_ROOT}/tools}"
CACHE_DIR="${CACHE_DIR:-${HPC_PROJECT_ROOT}/cache}"
SYNC_DIR="${SYNC_DIR:-${HPC_PROJECT_ROOT}/sync}"
INTERLINK_DIR="${INTERLINK_DIR:-${HPC_PROJECT_ROOT}/.interlink}"
INTERLINK_DATA_ROOT="${INTERLINK_DATA_ROOT:-${INTERLINK_DIR}/jobs}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-admin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-admin123}"
MINIO_HOST="${MINIO_HOST:-68.221.216.246}"
MINIO_PORT="${MINIO_PORT:-9000}"
MINIO_SCHEME="${MINIO_SCHEME:-http}"
MINIO_ALIAS="${MINIO_ALIAS:-myminio}"

mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
# ./mc --version

export ACCESS_KEY="$MINIO_ACCESS_KEY"
export SECRET_KEY="$MINIO_SECRET_KEY"

$TOOLS_DIR/mc alias set "$MINIO_ALIAS" \
  "${MINIO_SCHEME}://${MINIO_HOST}:${MINIO_PORT}" \
  "$ACCESS_KEY" \
  "$SECRET_KEY"

cd ..
mkdir -p "$CACHE_DIR"
mkdir -p "$SYNC_DIR"

cat > "$SYNC_DIR/sync-inputs.sh" <<EOF
#!/bin/bash

set -euo pipefail

export PATH=\$PATH:$TOOLS_DIR

echo "[wrapper] starting"

JOB_SCRIPT="\$1"

JOB_DIR="$(dirname "\$JOB_SCRIPT")"

ENVFILE="$(find "\$JOB_DIR" -name '*_envfile.properties' | head -n1)"

if [[ -f "\$ENVFILE" ]]; then

    echo "[wrapper] loading env file: \$ENVFILE"

    set -a
    source "\$ENVFILE"
    set +a

else
    echo "[wrapper] no env file found"
fi

CACHE_ROOT="$CACHE_DIR"

if [[ -n "\${INPUT_URI:-}" ]]; then

    if [[ "\$INPUT_URI" == *".."* ]]; then
        echo "invalid input path"
        exit 1
    fi

    if [[ "\$INPUT_URI" == /* ]]; then
        echo "absolute paths forbidden"
        exit 1
    fi

    CACHE_DIR="\$CACHE_ROOT/\$INPUT_URI"

    LOCKFILE="\${CACHE_DIR}.lock"

    mkdir -p "$(dirname "\$CACHE_DIR")"

    (
        flock -x 200

        mkdir -p "\$CACHE_DIR"

        echo "[wrapper] syncing input cache"

        mc mirror \
          "${MINIO_ALIAS}/$INPUT_URI" \
            "\$CACHE_DIR"

    ) 200>"\$LOCKFILE"

    echo "[wrapper] cache ready: \$CACHE_DIR"

    echo "INPUT_CACHE_DIR=\$CACHE_DIR" >> "\$ENVFILE"
    echo "INTERLINK_JOB_DIR=\$JOB_DIR" >> "\$ENVFILE"
fi

echo "[wrapper] launching original job"

exec /bin/bash "$JOB_SCRIPT"
EOF

chmod +x "$SYNC_DIR/sync-inputs.sh"

cat > "$SYNC_DIR/sync-daemon.sh" <<EOF
#!/bin/bash

set -euo pipefail

export PATH=\$PATH:$TOOLS_DIR

LOCAL_JOBS="${INTERLINK_DATA_ROOT}"

REMOTE_ROOT="${MINIO_ALIAS}/results"

SYNC_INTERVAL=60

echo "=== JOB SYNC DAEMON STARTED ==="

while true; do

  echo
  echo "=== $(date) ==="
  echo "Syncing job directories..."

  find "\$LOCAL_JOBS" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d | while read JOBDIR; do

      JOBNAME="$(basename "\$JOBDIR")"

      echo "Syncing \$JOBNAME"

      mc mirror \
        "\$JOBDIR" \
        "\$REMOTE_ROOT/\$JOBNAME" || true

  done

  sleep "\$SYNC_INTERVAL"

done

EOF

chmod +x "$SYNC_DIR/sync-daemon.sh"

mkdir -p ~/.config/systemd/user
touch "$SYNC_DIR/sync-daemon.log"

cat > ~/.config/systemd/user/sync-daemon.service <<EOF
[Unit]
Description=MinIO Sync Daemon
After=network.target

[Service]
Type=simple

ExecStart=${SYNC_DIR}/sync-daemon.sh

Restart=always
RestartSec=5

StandardOutput=append:${SYNC_DIR}/sync-daemon.log
StandardError=append:${SYNC_DIR}/sync-daemon.log

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sync-daemon

# systemctl --user status sync-daemon
# tail -f ${SYNC_DIR}/sync-daemon.log

# cd ${HPC_PROJECT_ROOT}/.interlink/jobs