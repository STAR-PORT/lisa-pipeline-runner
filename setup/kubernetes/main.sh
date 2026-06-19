#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/.env}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

if [[ -f "$CONFIG_FILE" ]]; then
  echo "Loading Kubernetes setup configuration from $CONFIG_FILE"
  set -a
  source "$CONFIG_FILE"
  set +a
else
  echo "Configuration file not found: $CONFIG_FILE"
  echo "Create the file by copying $SCRIPT_DIR/.env.example and editing it."
  exit 1
fi

echo "Running Kubernetes setup with the following values:"
echo "  K8S_VERSION=$K8S_VERSION"
echo "  K8S_FULL_VERSION=$K8S_FULL_VERSION"
echo "  K8S_PKG_VERSION=$K8S_PKG_VERSION"
echo "  CALICO_VERSION=$CALICO_VERSION"
echo "  ARGO_VERSION=$ARGO_VERSION"
echo "  INTERLINK_VERSION=$INTERLINK_VERSION"
echo "  INTERLINK_INSTALL_DIR=$INTERLINK_INSTALL_DIR"
echo "  SIDECAR_SSH_USER=$SIDECAR_SSH_USER"
echo "  SIDECAR_SSH_HOST=$SIDECAR_SSH_HOST"
echo "  SIDECAR_LOCAL_HOST=$SIDECAR_LOCAL_HOST"
echo "  SIDECAR_LOCAL_PORT=$SIDECAR_LOCAL_PORT"
echo "  SIDECAR_REMOTE_PORT=$SIDECAR_REMOTE_PORT"
echo "  INTERLINK_DATA_ROOT=$INTERLINK_DATA_ROOT"
echo "  INTERLINK_NODE_NAME=$INTERLINK_NODE_NAME"
echo "  SLURM_ACCOUNT=$SLURM_ACCOUNT"
echo "  SLURM_PARTITION=$SLURM_PARTITION"

echo "[STEP 1] Running kubernetes node setup"
bash "$SCRIPT_DIR/1-kubernetes.sh"

echo "[STEP 2] Installing Argo components"
bash "$SCRIPT_DIR/2-argo.sh"

echo "[STEP 3] Installing InterLink bridge"
bash "$SCRIPT_DIR/3-bridge.sh"

echo "[STEP 4] Applying Templates"
for tmpl in argo_templates/*.yaml.tmpl; do
  out="/tmp/$(basename "${tmpl%.tmpl}")"
  envsubst < "$tmpl" > "$out"
  kubectl apply -f "$out"
done

echo "Kubernetes setup complete."
