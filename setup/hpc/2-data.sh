#!/usr/bin/env bash
set -euo pipefail

# Customizable environment variables:
#   HPC_PROJECT_ROOT  - base project path (default: /projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner)
#   TOOLS_DIR         - tool install path (default: ${HPC_PROJECT_ROOT}/tools)
#   DATA_DIR         - local data root (default: ${HPC_PROJECT_ROOT}/data)
#   SYNC_DIR          - sync script directory (default: ${HPC_PROJECT_ROOT}/sync)
#   INTERLINK_DIR     - InterLink state directory (default: ${HPC_PROJECT_ROOT}/.interlink)
#   MINIO_ACCESS_KEY  - MinIO access key (default: admin)
#   MINIO_SECRET_KEY  - MinIO secret key (default: admin123)
#   MINIO_HOST        - MinIO host (default: 68.221.216.246)
#   MINIO_PORT        - MinIO port (default: 9000)
#   MINIO_SCHEME      - MinIO scheme (default: http)
#   MINIO_ALIAS       - MinIO alias name (default: myminio)
#   MINIO_REMOTE_ROOT - remote sync root (default: ${MINIO_ALIAS}/results)

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner}"
TOOLS_DIR="${TOOLS_DIR:-${HPC_PROJECT_ROOT}/tools}"
DATA_DIR="${DATA_DIR:-${HPC_PROJECT_ROOT}/data}"
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
mkdir -p "$DATA_DIR"
mkdir -p "$SYNC_DIR"

cat > "$SYNC_DIR/sync-data.sh" <<EOF
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

DATA_ROOT="$DATA_DIR"

if [[ -n "\${INPUT_URI:-}" ]]; then
    echo "[wrapper] input sync ongoing"

    if [[ "\$INPUT_URI" == *".."* ]]; then
        echo "invalid input path"
        exit 1
    fi

    if [[ "\$INPUT_URI" != "/users/\$ARGO_USER"* ]] && [[ "\$INPUT_URI" != "/shared"* ]]; then
        echo "input path must start with '/users/\$ARGO_USER' or '/shared'"
        exit 1
    fi

    INPUT_PATH="\${INPUT_URI#/}"
    INPUT_DIR="\$DATA_ROOT/\$INPUT_PATH"

    LOCKFILE="\${INPUT_DIR}.lock"

    mkdir -p "$(dirname "\$INPUT_DIR")"

    (
        flock -x 200

        mkdir -p "\$INPUT_DIR"

        echo "[wrapper] syncing input data"

                mc mirror \
                    "${MINIO_ALIAS}/\$INPUT_PATH" \
                        "\$INPUT_DIR"

    ) 200>"\$LOCKFILE"

    echo "[wrapper] data ready: \$INPUT_DIR"
fi

echo "[wrapper] launching original job"

USER_DIR="${DATA_DIR}/\$ARGO_USER"

sed -i \
  "s|singularity exec |singularity exec -B \${USER_DIR}:/\$ARGO_USER |" \
  "$JOB_SCRIPT"

 /bin/bash "\$JOB_SCRIPT"

if [[ -n "\${OUTPUT_URI:-}" ]]; then
    echo "[wrapper] output sync ongoing"

    if [[ "\$OUTPUT_URI" == *".."* ]]; then
        echo "invalid output path"
        exit 1
    fi

    if [[ "\$OUTPUT_URI" != "/users/\$ARGO_USER"* ]] && [[ "\$OUTPUT_URI" != "/shared"* ]]; then
        echo "output path must start with '/users/\$ARGO_USER' or '/shared'"
        exit 1
    fi

    OUTPUT_PATH="\${OUTPUT_URI#/}"
    OUTPUT_DIR="\$DATA_ROOT/\$OUTPUT_PATH"
    
    mc mirror \
      --overwrite \
      "\$OUTPUT_DIR" \
      "${MINIO_ALIAS}/\$OUTPUT_PATH"

    echo "[wrapper] output sync complete"
fi

echo "[wrapper] done"
EOF

chmod +x "$SYNC_DIR/sync-data.sh"


# cd ${HPC_PROJECT_ROOT}/.interlink/jobs