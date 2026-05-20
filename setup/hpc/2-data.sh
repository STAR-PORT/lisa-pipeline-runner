mkdir -p /projects/EEHPC-DEV-2026D02-075/tools
cd /projects/EEHPC-DEV-2026D02-075/tools
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
# ./mc --version

export ACCESS_KEY=admin
export SECRET_KEY=admin123

/projects/EEHPC-DEV-2026D02-075/tools/mc alias set myminio \
  http://68.221.216.246:9000 \
  $ACCESS_KEY \
  $SECRET_KEY

cd ..
mkdir -p /projects/EEHPC-DEV-2026D02-075/cache
mkdir -p /projects/EEHPC-DEV-2026D02-075/sync

cat > /projects/EEHPC-DEV-2026D02-075/sync/sync-inputs.sh <<'EOF'
#!/bin/bash

set -euo pipefail

export PATH=/projects/EEHPC-DEV-2026D02-075/tools:$PATH

echo "[wrapper] starting"

JOB_SCRIPT="$1"

JOB_DIR="$(dirname "$JOB_SCRIPT")"

ENVFILE="$(find "$JOB_DIR" -name '*_envfile.properties' | head -n1)"

if [[ -f "$ENVFILE" ]]; then

    echo "[wrapper] loading env file: $ENVFILE"

    set -a
    source "$ENVFILE"
    set +a

else
    echo "[wrapper] no env file found"
fi

CACHE_ROOT="/projects/EEHPC-DEV-2026D02-075/cache"

if [[ -n "${INPUT_URI:-}" ]]; then

    if [[ "$INPUT_URI" == *".."* ]]; then
        echo "invalid input path"
        exit 1
    fi

    if [[ "$INPUT_URI" == /* ]]; then
        echo "absolute paths forbidden"
        exit 1
    fi

    CACHE_DIR="$CACHE_ROOT/$INPUT_URI"

    LOCKFILE="${CACHE_DIR}.lock"

    mkdir -p "$(dirname "$CACHE_DIR")"

    (
        flock -x 200

        mkdir -p "$CACHE_DIR"

        echo "[wrapper] syncing input cache"

        mc mirror \
            "myminio/$INPUT_URI" \
            "$CACHE_DIR"

    ) 200>"$LOCKFILE"

    echo "[wrapper] cache ready: $CACHE_DIR"

    echo "INPUT_CACHE_DIR=$CACHE_DIR" >> "$ENVFILE"
    echo "INTERLINK_JOB_DIR=$JOB_DIR" >> "$ENVFILE"
fi

echo "[wrapper] launching original job"

exec /bin/bash "$JOB_SCRIPT"
EOF

chmod +x /projects/EEHPC-DEV-2026D02-075/sync/sync-inputs.sh

cat > /projects/EEHPC-DEV-2026D02-075/sync/sync-daemon.sh <<'EOF'
#!/bin/bash

set -euo pipefail

export PATH=$PATH:/projects/EEHPC-DEV-2026D02-075/tools

LOCAL_JOBS="/projects/EEHPC-DEV-2026D02-075/.interlink/jobs"

REMOTE_ROOT="myminio/results"

SYNC_INTERVAL=60

echo "=== JOB SYNC DAEMON STARTED ==="

while true; do

  echo
  echo "=== $(date) ==="
  echo "Syncing job directories..."

  find "$LOCAL_JOBS" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d | while read JOBDIR; do

      JOBNAME="$(basename "$JOBDIR")"

      echo "Syncing $JOBNAME"

      mc mirror \
        "$JOBDIR" \
        "$REMOTE_ROOT/$JOBNAME" || true

  done

  sleep "$SYNC_INTERVAL"

done

EOF

chmod +x /projects/EEHPC-DEV-2026D02-075/sync/sync-daemon.sh

mkdir -p ~/.config/systemd/user
touch /projects/EEHPC-DEV-2026D02-075/sync/sync-daemon.log

cat > ~/.config/systemd/user/sync-daemon.service <<'EOF'
[Unit]
Description=MinIO Sync Daemon
After=network.target

[Service]
Type=simple

ExecStart=/projects/EEHPC-DEV-2026D02-075/sync/sync-daemon.sh

Restart=always
RestartSec=5

StandardOutput=append:/projects/EEHPC-DEV-2026D02-075/sync/sync-daemon.log
StandardError=append:/projects/EEHPC-DEV-2026D02-075/sync/sync-daemon.log

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sync-daemon

# systemctl --user status sync-daemon
# tail -f /projects/EEHPC-DEV-2026D02-075/sync/sync-daemon.log

# cd /projects/EEHPC-DEV-2026D02-075/.interlink/jobs