#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

echo "[1/3] Stopping MinIO container"
docker stop minio >/dev/null 2>&1 || true

echo "[2/3] Removing MinIO container"
docker rm minio >/dev/null 2>&1 || true

echo "[3/3] Cleanup complete"
echo "MinIO container removed. Docker image and other Docker resources are left intact."
