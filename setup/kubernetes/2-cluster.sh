# On-Premises Kubernetes Cluster Setup Script
# This script sets up the environment inside a kubernetes cluster

#!/usr/bin/env bash
set -euo pipefail

ARGO_VERSION="v3.7.12"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

echo "[1/5] Installing CNI (Calico) ..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# Wait until node is Ready
kubectl wait --for=condition=Ready node/ulisses --timeout=300s || true
# same as > sudo kubectl get pods -n kube-system

echo "[2/5] Disabeling taint (required for argo) ..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

echo "[3/5] Installing Argo Workflows ..."
# Create namespace
kubectl create namespace argo || true
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.7.12/install.yaml

# Waiting for Argo components to be ready
kubectl wait --for=condition=Ready pods --all -n argo --timeout=300s || true
# same as > sudo kubectl get pods -n argo

echo "[4/5] Exposing Argo Server (NodePort for local access) ..."

kubectl patch svc argo-server -n argo -p '{
  "spec": {
    "type": "NodePort"
  }
}'

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