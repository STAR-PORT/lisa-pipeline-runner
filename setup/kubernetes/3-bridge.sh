#!/usr/bin/env bash
# InterLink bridge installer for Kubernetes.
# This script installs InterLink API and Virtual Kubelet support on a Debian host
# and creates a persistent SSH tunnel to the remote HPC Sidecar.
# 
#  Prerequisite: SIDECAR_SSH_KEY_PATH in machine environment must have a valid SSH private key with access to the HPC sidecar host.
#
# Customizable environment variables:
#  INTERLINK_INSTALL_DIR     - Directory to install InterLink binaries and configs (default: /opt/interlink)
#  INTERLINK_VERSION         - InterLink release version to install (default: 0.6.1)
#  SIDECAR_SSH_USER          - SSH username for connecting to the HPC sidecar
#  SIDECAR_SSH_HOST          - SSH host for connecting to the HPC sidecar
#  SIDECAR_SSH_KEY_PATH      - SSH private key path for the remote host (default: /root/.ssh/id_ed25519)
#  SIDECAR_LOCAL_HOST        - Local interface to bind the SSH tunnel (default: 10.227.208.123)
#  SIDECAR_LOCAL_PORT        - Local port for the SSH tunnel (default: 5000)
#  SIDECAR_REMOTE_PORT       - Remote port for the SSH tunnel (default: 4000)
#  INTERLINK_DATA_ROOT       - Root directory for InterLink data (default: /tmp/interlink)
#  INTERLINK_NODE_NAME       - Kubernetes node name for the Virtual Kubelet (default: interlink-node)
#
# Example:
#   SIDECAR_SSH_HOST=example.edu INTERLINK_SIDECAR_HOST=sidecar.example.edu ./setup/kubernetes/3-bridge.sh

set -euo pipefail

INTERLINK_INSTALL_DIR="${INTERLINK_INSTALL_DIR:-/opt/interlink}"
INTERLINK_VERSION="${INTERLINK_VERSION:-0.6.1}"
SIDECAR_SSH_USER="${SIDECAR_SSH_USER:-isabelmoutinho}"
SIDECAR_SSH_HOST="${SIDECAR_SSH_HOST:-ln01.deucalion.macc.fccn.pt}"
SIDECAR_SSH_KEY_PATH="${SIDECAR_SSH_KEY_PATH:-/root/.ssh/id_ed25519}"
SIDECAR_LOCAL_HOST="${SIDECAR_LOCAL_HOST:-10.227.208.123}"
SIDECAR_LOCAL_PORT="${SIDECAR_LOCAL_PORT:-5000}"
SIDECAR_REMOTE_PORT="${SIDECAR_REMOTE_PORT:-4000}"
INTERLINK_DATA_ROOT="${INTERLINK_DATA_ROOT:-/tmp/interlink}"
INTERLINK_NODE_NAME="${INTERLINK_NODE_NAME:-interlink-node}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

for cmd in wget ssh tee systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command '$cmd' is missing. Install it before running this script."
    exit 1
  fi
done

echo "[1/6] Preparing InterLink install directory: $INTERLINK_INSTALL_DIR"
mkdir -p "$INTERLINK_INSTALL_DIR"
chown root:root "$INTERLINK_INSTALL_DIR"
chmod 755 "$INTERLINK_INSTALL_DIR"
cd "$INTERLINK_INSTALL_DIR"

echo "[2/6] Downloading InterLink binaries for version $INTERLINK_VERSION"
INTERLINK_RELEASE_BASE="https://github.com/interlink-hq/interLink/releases/download/${INTERLINK_VERSION}"
wget "$INTERLINK_RELEASE_BASE/interlink_Linux_x86_64"
chmod +x interlink_Linux_x86_64
wget "$INTERLINK_RELEASE_BASE/virtual-kubelet_Linux_x86_64"
chmod +x virtual-kubelet_Linux_x86_64

echo "[3/6] Writing InterLink configuration files"

tee "$INTERLINK_INSTALL_DIR/InterLinkConfig.yaml" >/dev/null <<EOF
# Use Unix socket for local communication
InterlinkAddress: "unix:///tmp/interlink.sock"
InterlinkPort: ""  # Not used for Unix sockets

# Remote plugin configuration
SidecarURL: "http://${SIDECAR_LOCAL_HOST}"
SidecarPort: "${SIDECAR_LOCAL_PORT}"

VerboseLogging: true
ErrorsOnlyLogging: false
DataRootFolder: "${INTERLINK_DATA_ROOT}"
EOF

tee "$INTERLINK_INSTALL_DIR/VirtualKubeletConfig.yaml" >/dev/null <<EOF
# Connect to Unix socket
InterlinkURL: "unix:///tmp/interlink.sock"
InterlinkPort: ""  # Not used for Unix sockets

VerboseLogging: true
ErrorsOnlyLogging: false

# Node configuration
NodeName: "${INTERLINK_NODE_NAME}"
NodeLabels:
"interlink.cern.ch/provider": "remote-hpc"
EOF

echo "[4/6] Writing systemd service unit files"
tee /etc/systemd/system/interlink-api.service >/dev/null <<EOF
[Unit]
Description=InterLink API Server
After=network.target

[Service]
Environment=INTERLINKCONFIGPATH=${INTERLINK_INSTALL_DIR}/InterLinkConfig.yaml
ExecStart=${INTERLINK_INSTALL_DIR}/interlink_Linux_x86_64
WorkingDirectory=${INTERLINK_INSTALL_DIR}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

tee /etc/systemd/system/interlink-vk.service >/dev/null <<EOF
[Unit]
Description=Virtual Kubelet for InterLink
After=network.target interlink-api.service

[Service]
Environment=KUBECONFIG=/root/.kube/config
ExecStart=${INTERLINK_INSTALL_DIR}/virtual-kubelet_Linux_x86_64 \
  --nodename "${INTERLINK_NODE_NAME}" \
  --configpath ${INTERLINK_INSTALL_DIR}/VirtualKubeletConfig.yaml
WorkingDirectory=${INTERLINK_INSTALL_DIR}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

tee /etc/systemd/system/interlink-tunnel.service >/dev/null <<EOF
[Unit]
Description=Persistent SSH Tunnel to Slurm Sidecar
After=network.target

[Service]
ExecStart=/usr/bin/ssh -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i ${SIDECAR_SSH_KEY_PATH} \
    -N -L ${SIDECAR_LOCAL_HOST}:${SIDECAR_LOCAL_PORT}:localhost:${SIDECAR_REMOTE_PORT} \
    ${SIDECAR_SSH_USER}@${SIDECAR_SSH_HOST}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[5/6] Reloading systemd and enabling services"
systemctl daemon-reload
systemctl enable --now interlink-tunnel
systemctl enable --now interlink-api
systemctl enable --now interlink-vk

echo "[6/6] Service and node checks"

echo "InterLink bridge installation complete. Verify Kubernetes node connectivity with:"
echo "  kubectl get nodes"

# Logs
# sudo kubectl describe node interlink-node
# Service Logs Live
# sudo journalctl -u interlink-tunnel -f
# sudo journalctl -u interlink-api -f
# sudo journalctl -u interlink-vk -f
# Service Logs History
# sudo journalctl -u interlink-tunnel
# sudo journalctl -u interlink-api
# sudo journalctl -u interlink-vk

# Service Status
# sudo systemctl status interlink-tunnel
# sudo systemctl status interlink-api
# sudo systemctl status interlink-vk

# Control

# Service Start
# sudo systemctl start interlink-tunnel
# sudo systemctl start interlink-api
# sudo systemctl start interlink-vk

# Service Stop
# sudo systemctl stop interlink-tunnel
# sudo systemctl stop interlink-api
# sudo systemctl stop interlink-vk

# Service Restart
# sudo systemctl restart interlink-tunnel
# sudo systemctl restart interlink-api
# sudo systemctl restart interlink-vk

# Disable Autostart Service
# sudo systemctl disable interlink-tunnel
# sudo systemctl disable interlink-api
# sudo systemctl disable interlink-vk

