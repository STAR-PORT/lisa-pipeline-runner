# On-Premises Kubernetes Cluster Setup Script
# This script installs Argo Workflows and configures the cluster for local testing.
#
# Customizable environment variables:
#   ARGO_VERSION        - Argo Workflows release tag (default: v3.7.12)
#   CALICO_VERSION      - Calico manifest version (default: v3.28.0)
# Example:
#   ARGO_VERSION=v3.7.12 ./setup/kubernetes/2-cluster.sh

#!/usr/bin/env bash
set -euo pipefail

ARGO_VERSION="${ARGO_VERSION:-v3.7.12}"
CALICO_VERSION="${CALICO_VERSION:-v3.28.0}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required and was not found in PATH. Install kubectl before running this script."
  exit 1
fi

echo "[1/5] Installing CNI (Calico) ..."
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

echo "[2/5] Waiting for all cluster nodes to join..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s || true
echo "[2/5] Node readiness check complete."

echo "[3/5] Disabling control-plane node taints (required for Argo on a single-node cluster) ..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

echo "[3/5] Installing Argo Workflows ..."
# Create namespace
kubectl create namespace argo || true
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/install.yaml

# Waiting for Argo components to be ready
kubectl wait --for=condition=Ready pods --all -n argo --timeout=300s || true
# same as > sudo kubectl get pods -n argo

echo "[4/5] Exposing Argo Server (NodePort for local access) ..."

if kubectl get svc argo-server -n argo >/dev/null 2>&1; then
  kubectl patch svc argo-server -n argo -p '{
    "spec": {
      "type": "NodePort"
    }
  }'
else
  echo "Warning: argo-server service not found in namespace argo. Skipping NodePort patch."
fi

# kubectl patch deployment argo-server -n argo \
#  -p '{"spec": {"template": {"spec": {"containers": [{"name": "argo-server","args": ["server","--auth-mode=server"]}]}}}}'


echo "[5/5] Next steps:"
echo ""
echo "1. Get Argo server port:"
echo "   kubectl get svc argo-server -n argo"
echo ""
echo "2. Access UI:"
echo "   https://<your-node-ip>:<nodePort>"
echo ""
echo "3. Install Argo CLI (optional but recommended):"
echo "   curl -sLO https://github.com/argoproj/argo-workflows/releases/latest/download/argo-linux-amd64.gz"
echo "   gunzip argo-linux-amd64.gz"
echo "   chmod +x argo-linux-amd64"
echo "   sudo mv argo-linux-amd64 /usr/local/bin/argo"
echo ""
echo "4. Test a workflow:"
echo "   argo submit --watch https://raw.githubusercontent.com/argoproj/argo-workflows/master/examples/hello-world.yaml -n argo"