# On-Premises Kubernetes Setup Script
# This script sets up a single-node Kubernetes control-plane node on Debian.
# Run as root or via sudo on the target server.
#
# Customizable environment variables:
#   K8S_VERSION         - Kubernetes minor version (default: 1.35)
#   K8S_FULL_VERSION    - Kubernetes full version (default: 1.35.3)
#   K8S_PKG_VERSION     - Debian package version (default: ${K8S_FULL_VERSION}-1.1)
# Example:
#   K8S_VERSION=1.35 K8S_FULL_VERSION=1.35.3 ./setup/kubernetes/1-kubernetes.sh

#!/usr/bin/env bash
set -euo pipefail

# Ensure script runs as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer requires apt-get and can only run on Debian-based systems."
  exit 1
fi

K8S_VERSION="${K8S_VERSION:-1.35}"
K8S_FULL_VERSION="${K8S_FULL_VERSION:-1.35.3}"
K8S_PKG_VERSION="${K8S_PKG_VERSION:-${K8S_FULL_VERSION}-1.1}"

if [ -f /etc/kubernetes/admin.conf ]; then
  echo "Kubernetes already initialized on this host. Exiting without changes."
  exit 0
fi

echo "[1/10] Updating system..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg lsb-release git

echo "[2/10] Disabling swap (required by Kubernetes)..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "[3/10] Loading kernel modules and sysctl..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

echo "[4/10] Installing containerd..."
apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Set correct CNI bin directory
sed -i 's|bin_dir = "/usr/lib/cni"|bin_dir = "/opt/cni/bin"|' /etc/containerd/config.toml

# Ensure systemd cgroups (required for kubeadm stability)
sed -i '/SystemdCgroup/s/false/true/' /etc/containerd/config.toml

# Ensure correct sandbox (pause) image
sed -i '/sandbox_image/s|pause:.*"|pause:3.10.1"|' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo "[5/10] Adding Kubernetes repository..."
mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  | tee /etc/apt/sources.list.d/kubernetes.list

echo "[6/10] Installing Kubernetes components (kubeadm, kubelet, kubectl) ..."
apt-get update
apt-get install -y \
  kubelet=${K8S_PKG_VERSION} \
  kubeadm=${K8S_PKG_VERSION} \
  kubectl=${K8S_PKG_VERSION}

# Prevent automatic upgrades (important)
apt-mark hold kubelet kubeadm kubectl

echo "[7/10] Restricting kubectl to root/sudo usage only"
if command -v kubectl >/dev/null 2>&1; then
  chmod 750 "$(command -v kubectl)"
fi
if command -v kubeadm >/dev/null 2>&1; then
  chmod 750 "$(command -v kubeadm)"
fi
if command -v kubelet >/dev/null 2>&1; then
  chmod 750 "$(command -v kubelet)"
fi

systemctl enable kubelet

echo "[8/10] Applying basic system hardening..."

# Lock critical dirs
chmod 700 /root
mkdir -p /etc/kubernetes
chmod 755 /etc/kubernetes

echo "[9/10] Pre-pulling kubeadm images ..."
kubeadm config images pull --kubernetes-version v${K8S_FULL_VERSION}

echo "[9/10] Initializing cluster ..."
kubeadm init --kubernetes-version v${K8S_FULL_VERSION}

echo "[10/10] Installing root kubeconfig for sudo users"
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config

echo "Done"

# To start using your cluster, you need to run the following as a regular user:

#   mkdir -p $HOME/.kube
#   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#   sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Alternatively, if you are the root user, you can run:

#   export KUBECONFIG=/etc/kubernetes/admin.conf

# You should now deploy a pod network to the cluster.
# Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
#   https://kubernetes.io/docs/concepts/cluster-administration/addons/

# Then you can join any number of worker nodes by running the following on each as root:

# kubeadm join 10.0.2.15:6443 --token tw8bq9.j7qsf4a6mxs6g9j2 \
# 	--discovery-token-ca-cert-hash sha256:4883a2a5816b77db7074916d04879c052725127d63cbdb86395eb1c000998581 
