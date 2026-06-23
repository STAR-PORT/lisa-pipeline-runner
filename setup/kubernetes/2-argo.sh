# On-Premises Kubernetes Cluster Setup Script
# This script installs Argo Workflows and configures the cluster for local testing.
#
# Customizable environment variables:
#   ARGO_VERSION        - Argo Workflows release tag (default: v3.7.12)
#   CALICO_VERSION      - Calico manifest version (default: v3.28.0)
#   DEX_VERSION         - Dex release version (default: v2.37.0)
#   MACHINE_HOST        - Machine IP for Argo Server access (default: 10.227.208.123)
# Example:
#   ARGO_VERSION=v3.7.12 ./setup/kubernetes/2-argo.sh

#!/usr/bin/env bash
set -euo pipefail

ARGO_VERSION="${ARGO_VERSION:-v3.7.12}"
CALICO_VERSION="${CALICO_VERSION:-v3.28.0}"
DEX_VERSION="${DEX_VERSION:-v2.37.0}"
MACHINE_HOST="${MACHINE_HOST:-10.227.208.123}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (use sudo)"
  exit 1
fi

for cmd in kubectl htpasswd openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required but was not found in PATH."
    exit 1
  fi
done

echo "[1/10] Installing CNI (Calico) ..."
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

echo "[2/10] Waiting for all cluster nodes to join..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s || true
echo "[2/10] Node readiness check complete."


echo "[3/10] Disabling control-plane node taints (required for Argo on a single-node cluster) ..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

echo "[4/10] Installing Argo Workflows ..."
# Create namespace
kubectl create namespace argo || true
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/install.yaml

# Waiting for Argo components to be ready
kubectl wait --for=condition=Ready pods --all -n argo --timeout=300s || true
# same as > sudo kubectl get pods -n argo

ADMIN_BCRYPT="$(htpasswd -bnBC 10 "" "admin123" | tr -d ':\n')"

DEX_CLIENT_SECRET="$(openssl rand -hex 32)"


echo "[5/10] Generating self-signed TLS cert for Dex ..."
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /tmp/dex-tls.key \
  -out    /tmp/dex-tls.crt \
  -days   365 \
  -subj   "/CN=${MACHINE_HOST}" \
  -addext "subjectAltName=IP:${MACHINE_HOST}" 2>/dev/null

kubectl create secret generic dex-tls -n argo \
  --from-file=tls.crt=/tmp/dex-tls.crt \
  --from-file=tls.key=/tmp/dex-tls.key \
  --dry-run=client -o yaml | kubectl apply -f -

rm -f /tmp/dex-tls.crt /tmp/dex-tls.key


echo "[6/10] Deploying Dex ..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: dex-config
  namespace: argo
data:
  config.yaml: |
    issuer: https://${MACHINE_HOST}:32000/dex

    storage:
      type: memory

    web:
      https: 0.0.0.0:5556
      tlsCert: /etc/dex/tls/tls.crt
      tlsKey:  /etc/dex/tls/tls.key

    enablePasswordDB: true
    staticPasswords:
      - email: "admin@example.com"
        hash: "${ADMIN_BCRYPT}"
        username: "admin"
        userID: "argo-admin-00001"

    staticClients:
      - id: argo-workflows
        name: Argo Workflows
        secret: "${DEX_CLIENT_SECRET}"
        redirectURIs:
          - http://${MACHINE_HOST}:32746/oauth2/callback
EOF

# Dex Deployment
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dex
  namespace: argo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dex
  template:
    metadata:
      labels:
        app: dex
    spec:
      containers:
        - name: dex
          image: ghcr.io/dexidp/dex:${DEX_VERSION}
          command: ["/usr/local/bin/dex", "serve", "/etc/dex/cfg/config.yaml"]
          ports:
            - containerPort: 5556
          volumeMounts:
            - name: config
              mountPath: /etc/dex/cfg
            - name: tls
              mountPath: /etc/dex/tls
      volumes:
        - name: config
          configMap:
            name: dex-config
        - name: tls
          secret:
            secretName: dex-tls
EOF

# Dex Service — NodePort 32000 → container port 5556
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: dex
  namespace: argo
spec:
  type: NodePort
  selector:
    app: dex
  ports:
    - name: https
      port: 5556
      targetPort: 5556
      nodePort: 32000
EOF

kubectl wait --for=condition=Ready pod -l app=dex -n argo --timeout=120s


echo "[7/10] Creating OAuth2 client secrets ..."

kubectl create secret generic argo-workflows-sso -n argo \
  --from-literal=client-id=argo-workflows \
  --from-literal=client-secret="${DEX_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -


echo "[8/10] Configuring Argo Server SSO ..."

kubectl create secret generic argo-workflows-sso -n argo \
  --from-literal=client-id=argo-workflows \
  --from-literal=client-secret="${DEX_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl patch configmap workflow-controller-configmap -n argo --type=merge -p "
data:
  sso: |
    issuer: https://${MACHINE_HOST}:32000/dex
    clientId:
      name: argo-workflows-sso
      key: client-id
    clientSecret:
      name: argo-workflows-sso
      key: client-secret
    redirectUrl: http://${MACHINE_HOST}:32746/oauth2/callback
    scopes:
      - openid
      - profile
      - email
    insecureSkipVerify: true
"

echo "[9/10] Exposing Argo Server with SSO ..."

kubectl patch deployment argo-server -n argo --type=strategic -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "argo-server",
          "args": [
            "server",
            "--auth-mode=sso",
            "--auth-mode=client",
            "--secure=false"
          ],
          "readinessProbe": {
            "httpGet": {
              "scheme": "HTTP"
            }
          }
        }]
      }
    }
  }
}'

kubectl patch svc argo-server -n argo -p \
  '{"spec":{"type":"NodePort","ports":[{"port":2746,"targetPort":2746,"nodePort":32746,"name":"web"}]}}'

kubectl rollout restart deployment/argo-server -n argo
kubectl rollout status deployment/argo-server -n argo --timeout=120s
# kubectl get pods -n argo

echo "[10/10] Creating RBAC roles and bindings ..."
sudo kubectl apply -f - <<EOF
# Role + binding for the default SA that runs user workflows
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-workflow-role
  namespace: default
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "create", "delete", "patch"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["argoproj.io"]
  resources: ["workflows", "workflowtemplates", "workflowtaskresults"]
  verbs: ["get", "list", "watch", "create", "delete", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-workflow-rolebinding
  namespace: default
subjects:
- kind: ServiceAccount
  name: default
  namespace: default
roleRef:
  kind: Role
  name: argo-workflow-role
  apiGroup: rbac.authorization.k8s.io
---
# SA that owns and executes the system CronWorkflow
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-system-scheduler
  namespace: argo
---
# Give the service account permission to execute workflows in the argo namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-system-scheduler-binding
  namespace: argo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argo-workflow-role
subjects:
- kind: ServiceAccount
  name: argo-system-scheduler
  namespace: argo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-system-scheduler-default-binding
  namespace: default                          # permission is in default
roleRef:
  kind: Role
  name: argo-workflow-role                    # reuse the existing role
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: argo-system-scheduler                 # SA lives in argo namespace
  namespace: argo
---
# SA that SSO users are mapped to when viewing the argo namespace
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-readonly
  namespace: argo
  annotations:
    workflows.argoproj.io/rbac-rule: "true"          # matches all SSO users
    workflows.argoproj.io/rbac-rule-precedence: "0"  # lowest precedence (fallback)
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argo-readonly-role
  namespace: argo
rules:
- apiGroups: ["argoproj.io"]
  resources: ["workflows", "cronworkflows", "workflowtemplates"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argo-readonly-binding
  namespace: argo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: argo-readonly-role
subjects:
- kind: ServiceAccount
  name: argo-readonly
  namespace: argo
EOF


echo ""
echo "======================================================"
echo "  Setup complete!"
echo "======================================================"
echo ""
echo "  Argo Workflows UI  :  http://${MACHINE_HOST}:32746"
echo "  Dex OIDC issuer    :  https://${MACHINE_HOST}:32000/dex"
echo ""
echo "  Login credentials"
echo "    Email   : admin@example.com"
echo "    Password: admin123"
echo ""
echo "  NOTE: clicking Login redirects to Dex over HTTPS."
echo "  Accept the self-signed certificate warning in the browser."
echo ""
echo "  To add more users, edit the dex-config ConfigMap:"
echo "    kubectl edit configmap dex-config -n argo"
echo "  Then restart Dex:"
echo "    kubectl rollout restart deployment/dex -n argo"
echo "======================================================"
