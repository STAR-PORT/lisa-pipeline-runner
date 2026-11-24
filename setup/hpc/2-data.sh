#!/usr/bin/env bash
set -euo pipefail

# Install the MinIO client used by the Argo sync module on remote Slurm jobs.

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner}"
HPC_TOOLS_DIR="${HPC_TOOLS_DIR:-${HPC_PROJECT_ROOT}/tools}"
HPC_DATA_DIR="${HPC_DATA_DIR:-${HPC_PROJECT_ROOT}/data}"
MC_VERSION="${MC_VERSION:-RELEASE.2025-08-13T08-35-41Z}"

mkdir -p "$HPC_TOOLS_DIR" "$HPC_DATA_DIR/users/system"
wget -O "$HPC_TOOLS_DIR/mc" \
  "https://github.com/minio/mc/releases/download/${MC_VERSION}/mc.linux-amd64.${MC_VERSION}"
chmod 755 "$HPC_TOOLS_DIR/mc"