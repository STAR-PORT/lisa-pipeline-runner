#!/usr/bin/env bash
set -euo pipefail

# Install the MinIO client used by the Argo sync module on remote Slurm jobs.

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner}"
HPC_TOOLS_DIR="${HPC_TOOLS_DIR:-${HPC_PROJECT_ROOT}/tools}"
HPC_DATA_DIR="${HPC_DATA_DIR:-${HPC_PROJECT_ROOT}/data}"
MC_VERSION="${MC_VERSION:-RELEASE.2025-02-08T19-14-21Z}"

mkdir -p "$HPC_TOOLS_DIR" "$HPC_DATA_DIR/users/system"
wget -O "$HPC_TOOLS_DIR/mc" \
  "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_VERSION}"
chmod 755 "$HPC_TOOLS_DIR/mc"