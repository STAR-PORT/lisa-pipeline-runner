#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  echo "Loading HPC configuration from $CONFIG_FILE"
  set -a
  source "$CONFIG_FILE"
  set +a
else
  echo "Configuration file not found: $CONFIG_FILE"
  echo "Copy $SCRIPT_DIR/.env.example to $CONFIG_FILE and edit it.
"
  exit 1
fi

echo "[STEP 1] Running HPC bridge setup"
bash "$SCRIPT_DIR/1-bridge.sh"

echo "[STEP 2] Running HPC data setup"
bash "$SCRIPT_DIR/2-data.sh"

echo "HPC setup complete."
