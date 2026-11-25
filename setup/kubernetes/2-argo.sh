# On-Premises Kubernetes Cluster Setup Script
# This script installs Argo Workflows and configures the cluster for local testing.
#
# Customizable environment variables:
#   ARGO_VERSION        - Argo Workflows release tag (default: v3.7.12)
#   CALICO_VERSION      - Calico manifest version (default: v3.33.1)
#   DEX_VERSION         - Dex release version (default: v2.37.0)
#   MACHINE_HOST        - Machine IP for Argo Server access (default: K8S_NODE_IP)
# Example:
#   ARGO_VERSION=v3.7.12 ./setup/kubernetes/2-argo.sh

#!/usr/bin/env bash
set -euo pipefail

ARGO_VERSION="${ARGO_VERSION:-v3.7.12}"
ARGO_EXECUTOR_IMAGE="${ARGO_EXECUTOR_IMAGE:-quay.io/argoproj/argoexec:${ARGO_VERSION}}"
CALICO_VERSION="${CALICO_VERSION:-v3.33.1}"
DEX_VERSION="${DEX_VERSION:-v2.37.0}"
MACHINE_HOST="${MACHINE_HOST:-${K8S_NODE_IP:-127.0.0.1}}"
GARAGE_IMAGE="${GARAGE_IMAGE:-dxflrs/garage:v2.5.0}"
GARAGE_DATA_DIR="${GARAGE_DATA_DIR:-/var/lib/lisa-garage}"
OBJECT_STORE_NODE_PORT="${OBJECT_STORE_NODE_PORT:-30900}"
OBJECT_STORE_BUCKET="${OBJECT_STORE_BUCKET:-lisa}"
OBJECT_STORE_ACCESS_KEY="${OBJECT_STORE_ACCESS_KEY:-}"
OBJECT_STORE_SECRET_KEY="${OBJECT_STORE_SECRET_KEY:-}"
HPC_FORWARD_BIND_ADDRESS="${HPC_FORWARD_BIND_ADDRESS:-10.1.0.2}"
OBJECT_STORE_FORWARD_PORT="${OBJECT_STORE_FORWARD_PORT:-19001}"

if [[ -z "${ARGO_ADMIN_PASSWORD:-}" ]]; then
  echo "ARGO_ADMIN_PASSWORD must be set in setup/kubernetes/.env or the environment." >&2
  exit 1
fi

if [[ -z "$OBJECT_STORE_ACCESS_KEY" || -z "$OBJECT_STORE_SECRET_KEY" ]]; then
  echo "OBJECT_STORE_ACCESS_KEY and OBJECT_STORE_SECRET_KEY must be set." >&2
  exit 1
fi

if [[ ${#OBJECT_STORE_ACCESS_KEY} -lt 8 ]]; then
  echo "OBJECT_STORE_ACCESS_KEY must be at least 8 characters for Garage." >&2
  exit 1
fi

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
# sudo apt update && sudo apt install apache2-utils

echo "[1/11] Installing CNI (Calico) ..."
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

echo "[2/11] Waiting for all cluster nodes to join..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s || true
echo "[2/11] Node readiness check complete."


echo "[3/11] Disabling control-plane node taints (required for Argo on a single-node cluster) ..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

echo "[4/11] Installing Argo Workflows ..."
# Create namespace
kubectl create namespace argo || true
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/install.yaml

# Waiting for Argo components to be ready
kubectl wait --for=condition=Ready pods --all -n argo --timeout=300s || true
# same as > sudo kubectl get pods -n argo

echo "[5/11] Deploying Garage S3 storage ..."
mkdir -p "$GARAGE_DATA_DIR/meta" "$GARAGE_DATA_DIR/data"
chown -R 1000:1000 "$GARAGE_DATA_DIR"
chmod 750 "$GARAGE_DATA_DIR" "$GARAGE_DATA_DIR/meta" "$GARAGE_DATA_DIR/data"

EXISTING_GARAGE_RPC_SECRET="$(kubectl get secret lisa-garage-runtime -n default -o jsonpath='{.data.rpc-secret}' 2>/dev/null | base64 --decode 2>/dev/null || true)"
EXISTING_GARAGE_ADMIN_TOKEN="$(kubectl get secret lisa-garage-runtime -n default -o jsonpath='{.data.admin-token}' 2>/dev/null | base64 --decode 2>/dev/null || true)"
GARAGE_RPC_SECRET="${GARAGE_RPC_SECRET:-${EXISTING_GARAGE_RPC_SECRET:-$(openssl rand -hex 32)}}"
GARAGE_ADMIN_TOKEN="${GARAGE_ADMIN_TOKEN:-${EXISTING_GARAGE_ADMIN_TOKEN:-$(openssl rand -base64 32)}}"
OBJECT_STORE_CREDENTIALS_HASH="$(printf '%s:%s' "$OBJECT_STORE_ACCESS_KEY" "$OBJECT_STORE_SECRET_KEY" | openssl dgst -sha256 | awk '{print $NF}')"

kubectl create secret generic lisa-object-store-credentials -n default \
  --from-literal=accessKey="$OBJECT_STORE_ACCESS_KEY" \
  --from-literal=secretKey="$OBJECT_STORE_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic lisa-garage-runtime -n default \
  --from-literal=rpc-secret="$GARAGE_RPC_SECRET" \
  --from-literal=admin-token="$GARAGE_ADMIN_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: lisa-garage-config
  namespace: default
data:
  garage.toml: |
    metadata_dir = "/var/lib/garage/meta"
    data_dir = "/var/lib/garage/data"
    db_engine = "sqlite"
    replication_factor = 1
    rpc_bind_addr = "[::]:3901"
    rpc_public_addr = "127.0.0.1:3901"

    [s3_api]
    api_bind_addr = "[::]:3900"
    s3_region = "garage"

    [admin]
    api_bind_addr = "[::]:3903"
    metrics_require_token = true
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lisa-object-store
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lisa-object-store
  template:
    metadata:
      labels:
        app: lisa-object-store
      annotations:
        lisa-pipeline-runner/garage-credentials-sha256: "${OBJECT_STORE_CREDENTIALS_HASH}"
    spec:
      containers:
      - name: garage
        image: ${GARAGE_IMAGE}
        command: ["/garage"]
        args: ["server", "--single-node", "--default-bucket"]
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
        env:
        - name: GARAGE_CONFIG_FILE
          value: /etc/garage.toml
        - name: GARAGE_DEFAULT_BUCKET
          value: "${OBJECT_STORE_BUCKET}"
        - name: GARAGE_DEFAULT_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: lisa-object-store-credentials
              key: accessKey
        - name: GARAGE_DEFAULT_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: lisa-object-store-credentials
              key: secretKey
        - name: GARAGE_RPC_SECRET
          valueFrom:
            secretKeyRef:
              name: lisa-garage-runtime
              key: rpc-secret
        - name: GARAGE_ADMIN_TOKEN
          valueFrom:
            secretKeyRef:
              name: lisa-garage-runtime
              key: admin-token
        ports:
        - name: s3
          containerPort: 3900
        - name: rpc
          containerPort: 3901
        - name: admin
          containerPort: 3903
        volumeMounts:
        - name: metadata
          mountPath: /var/lib/garage/meta
        - name: data
          mountPath: /var/lib/garage/data
        - name: config
          mountPath: /etc/garage.toml
          subPath: garage.toml
          readOnly: true
        readinessProbe:
          tcpSocket:
            port: s3
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: metadata
        hostPath:
          path: ${GARAGE_DATA_DIR}/meta
          type: DirectoryOrCreate
      - name: data
        hostPath:
          path: ${GARAGE_DATA_DIR}/data
          type: DirectoryOrCreate
      - name: config
        configMap:
          name: lisa-garage-config
---
apiVersion: v1
kind: Service
metadata:
  name: lisa-object-store
  namespace: default
spec:
  type: NodePort
  selector:
    app: lisa-object-store
  ports:
  - name: s3
    port: 3900
    targetPort: s3
    nodePort: ${OBJECT_STORE_NODE_PORT}
EOF
kubectl rollout status deployment/lisa-object-store -n default --timeout=300s

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: artifact-repositories
  namespace: default
  annotations:
    workflows.argoproj.io/default-artifact-repository: garage-local
data:
  garage-local: |
    s3:
      endpoint: lisa-object-store.default.svc.cluster.local:3900
      bucket: ${OBJECT_STORE_BUCKET}
      region: garage
      insecure: true
      addressingStyle: path
      accessKeySecret:
        name: lisa-object-store-credentials
        key: accessKey
      secretKeySecret:
        name: lisa-object-store-credentials
        key: secretKey
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: artifact-repositories-hpc
  namespace: default
data:
  garage-hpc: |
    s3:
      endpoint: ${HPC_FORWARD_BIND_ADDRESS}:${OBJECT_STORE_FORWARD_PORT}
      bucket: ${OBJECT_STORE_BUCKET}
      region: garage
      insecure: true
      addressingStyle: path
      accessKeySecret:
        name: lisa-object-store-credentials
        key: accessKey
      secretKeySecret:
        name: lisa-object-store-credentials
        key: secretKey
EOF

ADMIN_BCRYPT="$(printf '%s\n' "$ARGO_ADMIN_PASSWORD" | htpasswd -nBC 10 -i "" | tr -d ':\n')"

DEX_CLIENT_SECRET="$(openssl rand -hex 32)"


echo "[6/11] Generating self-signed TLS cert for Dex ..."
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


echo "[7/11] Deploying Dex ..."

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


echo "[8/11] Creating OAuth2 client secrets ..."

kubectl create secret generic argo-workflows-sso -n argo \
  --from-literal=client-id=argo-workflows \
  --from-literal=client-secret="${DEX_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -


echo "[9/11] Configuring Argo Server SSO ..."

kubectl create secret generic argo-workflows-sso -n argo \
  --from-literal=client-id=argo-workflows \
  --from-literal=client-secret="${DEX_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl patch configmap workflow-controller-configmap -n argo --type=merge -p "
data:
  executor: |
    image: ${ARGO_EXECUTOR_IMAGE}
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

echo "[10/11] Exposing Argo Server with SSO ..."

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

echo "[11/11] Creating RBAC roles and bindings ..."
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
echo "    Password: value configured by ARGO_ADMIN_PASSWORD"
echo ""
echo "  NOTE: clicking Login redirects to Dex over HTTPS."
echo "  Accept the self-signed certificate warning in the browser."
echo ""
echo "  To add more users, edit the dex-config ConfigMap:"
echo "    kubectl edit configmap dex-config -n argo"
echo "  Then restart Dex:"
echo "    kubectl rollout restart deployment/dex -n argo"
echo "======================================================"
