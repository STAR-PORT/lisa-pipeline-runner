#!/usr/bin/env bash
set -euo pipefail

# This script sets up MinIO S3 storage on the global storage server.
# Run this to create the S3-compatible storage.

# sudo ssh -i ~/.ssh/lisa_key_0516.pem isabelmoutinho@68.221.216.246

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

MINIO_ROOT_USER="${MINIO_ROOT_USER:-admin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-admin123}"
MINIO_PORT="${MINIO_PORT:-9000}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"

apt update

apt install -y docker.io

systemctl enable --now docker

docker run -d \
  --name minio \
  -p ${MINIO_PORT}:9000 \
  -p ${MINIO_CONSOLE_PORT}:9001 \
  -e MINIO_ROOT_USER="${MINIO_ROOT_USER}" \
  -e MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" \
  quay.io/minio/minio server /data --console-address ":9001"