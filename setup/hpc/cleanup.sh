#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/EEHPC-DEV-2026D02-075}"
INTERLINK_DIR="${INTERLINK_DIR:-${HPC_PROJECT_ROOT}/.interlink}"
SYNC_DIR="${SYNC_DIR:-${HPC_PROJECT_ROOT}/sync}"
TOOLS_DIR="${TOOLS_DIR:-${HPC_PROJECT_ROOT}/tools}"
CACHE_DIR="${CACHE_DIR:-${HPC_PROJECT_ROOT}/cache}"

if [ "$(id -u)" -eq 0 ]; then
  echo "This cleanup should be run as the same user that installed the HPC services, not as root."
  exit 1
fi

echo "[1/4] Disabling user services"
systemctl --user disable --now interlink-sidecar >/dev/null 2>&1 || true
systemctl --user disable --now sync-daemon >/dev/null 2>&1 || true
systemctl --user daemon-reload >/dev/null 2>&1 || true

echo "[2/4] Removing user service files"
rm -f ~/.config/systemd/user/interlink-sidecar.service ~/.config/systemd/user/sync-daemon.service

echo "[3/4] Removing runtime directories"
rm -rf "$INTERLINK_DIR" "$SYNC_DIR" "$CACHE_DIR" "$TOOLS_DIR"

echo "[4/4] Cleanup complete"
echo "Removed HPC InterLink and sync setup directories."
