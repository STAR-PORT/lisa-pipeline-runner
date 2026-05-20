#!/usr/bin/env bash
set -euo pipefail

# This script sets up MinIO S3 storage on the global storage server.
# Run this to create the S3-compatible storage.

# sudo ssh -i ~/.ssh/lisa_key_0516.pem isabelmoutinho@68.221.216.246

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

apt update

apt install -y docker.io

systemctl enable --now docker

docker run -d \
  --name minio \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=admin \
  -e MINIO_ROOT_PASSWORD=admin123 \
  quay.io/minio/minio server /data --console-address ":9001"