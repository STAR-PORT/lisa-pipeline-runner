#!/usr/bin/env bash
# Requirements - HPC access: sudo ssh-keygen -t ed25519

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

INSTALL_DIR="/opt/interlink"
echo "[1/6] Preparing InterLink install directory: $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo chown root:root "$INSTALL_DIR"
sudo chmod 755 "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "[2/6] Downloading InterLink binaries"
wget https://github.com/interlink-hq/interLink/releases/download/0.6.1/interlink_Linux_x86_64
chmod +x interlink_Linux_x86_64
wget https://github.com/interlink-hq/interLink/releases/download/0.6.1/virtual-kubelet_Linux_x86_64
chmod +x virtual-kubelet_Linux_x86_64

echo "[3/6] Writing InterLink configuration files"
sudo tee "$INSTALL_DIR/InterLinkConfig.yaml" >/dev/null <<EOF
# Use Unix socket for local communication
InterlinkAddress: "unix:///tmp/interlink.sock"
InterlinkPort: ""  # Not used for Unix sockets

# Remote plugin configuration
SidecarURL: "http://192.168.67.64"
SidecarPort: "5000"

VerboseLogging: true
ErrorsOnlyLogging: false
DataRootFolder: "/tmp/interlink"
EOF

sudo tee "$INSTALL_DIR/VirtualKubeletConfig.yaml" >/dev/null <<EOF
# Connect to Unix socket
InterlinkURL: "unix:///tmp/interlink.sock"
InterlinkPort: ""  # Not used for Unix sockets

VerboseLogging: true
ErrorsOnlyLogging: false

# Node configuration
NodeName: "my-interlink-node"
NodeLabels:
"interlink.cern.ch/provider": "remote-hpc"
EOF

echo "[4/6] Writing systemd service unit files"
sudo tee /etc/systemd/system/interlink-api.service >/dev/null <<EOF
[Unit]
Description=InterLink API Server
After=network.target

[Service]
Environment=INTERLINKCONFIGPATH=/opt/interlink/InterLinkConfig.yaml
ExecStart=/opt/interlink/interlink_Linux_x86_64
WorkingDirectory=/opt/interlink
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/interlink-vk.service >/dev/null <<EOF
[Unit]
Description=Virtual Kubelet for InterLink
After=network.target interlink-api.service

[Service]
Environment=KUBECONFIG=/root/.kube/config
ExecStart=/opt/interlink/virtual-kubelet_Linux_x86_64 \
    --nodename interlink-node \
    --configpath /opt/interlink/VirtualKubeletConfig.yaml
WorkingDirectory=/opt/interlink
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/interlink-tunnel.service >/dev/null <<EOF
[Unit]
Description=Persistent SSH Tunnel to Slurm Sidecar
After=network.target

[Service]
ExecStart=/usr/bin/ssh -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -N -L 192.168.67.64:5000:localhost:4000 isabelmoutinho@ln01.deucalion.macc.fccn.pt
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[5/6] Reloading systemd and enabling services"
sudo systemctl daemon-reload
sudo systemctl enable --now interlink-tunnel
sudo systemctl enable --now interlink-api
sudo systemctl enable --now interlink-vk

echo "[6/6] Service and node checks"

# Nodes
sudo kubectl get nodes

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

