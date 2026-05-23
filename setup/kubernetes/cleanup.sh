#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

INTERLINK_INSTALL_DIR="${INTERLINK_INSTALL_DIR:-/opt/interlink}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

echo "[1/6] Stopping and disabling services"
for svc in interlink-tunnel interlink-api interlink-vk kubelet; do
  if systemctl list-units --full -all | grep -q "^${svc}\.service"; then
    systemctl disable --now "${svc}" >/dev/null 2>&1 || true
  fi
done

echo "[2/6] Removing InterLink files"
rm -f /etc/systemd/system/interlink-api.service
rm -f /etc/systemd/system/interlink-vk.service
rm -f /etc/systemd/system/interlink-tunnel.service
rm -rf "$INTERLINK_INSTALL_DIR"
systemctl daemon-reload >/dev/null 2>&1 || true

echo "[3/6] Resetting Kubernetes cluster"
if command -v kubeadm >/dev/null 2>&1; then
  kubeadm reset -f || true
fi
rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /var/lib/cni /run/kubeadm /run/flannel /run/calico /run/kubernetes /var/run/kubernetes
rm -rf /root/.kube

echo "[4/6] Removing CNI and networking state"
rm -rf /etc/cni /opt/cni /var/lib/calico /var/log/pods /var/log/containers

echo "[5/6] Removing Kubernetes and container runtime packages"
if command -v apt-get >/dev/null 2>&1; then
  apt-get purge -y kubelet kubeadm kubectl containerd || true
  apt-get autoremove -y || true
  rm -f /etc/apt/sources.list.d/kubernetes.list
  rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  rm -f /etc/containerd/config.toml
  apt-get update || true
fi

echo "[6/6] Cleanup complete"

echo "The Kubernetes cluster and InterLink components have been removed from this host."
