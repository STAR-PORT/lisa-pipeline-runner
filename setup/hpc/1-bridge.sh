#!/usr/bin/env bash
set -euo pipefail

# Customizable environment variables:
#   HPC_PROJECT_ROOT          - root path for project files (default: /projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner)
#   HPC_USER                  - user to enable lingering for (default: current user)
#   INTERLINK_SIDECAR_VERSION - InterLink sidecar release version (default: 0.6.1)
#   INTERLINK_DIR             - InterLink install/config directory (default: ${HPC_PROJECT_ROOT}/.interlink)
#   INTERLINK_DATA_ROOT       - job data root inside InterLink (default: ${INTERLINK_DIR}/jobs)
#   HPC_TOOLS_DIR             - shared tools directory mounted into Slurm containers (default: ${HPC_PROJECT_ROOT}/tools)

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/F202500007HPCVLABUPORTO/isabelmoutinho/lisa-pipeline-runner}"
HPC_USER="${HPC_USER:-${USER:-$(whoami)}}"
INTERLINK_SIDECAR_VERSION="${INTERLINK_SIDECAR_VERSION:-0.6.1}"
INTERLINK_DIR="${INTERLINK_DIR:-${HPC_PROJECT_ROOT}/.interlink}"
INTERLINK_DATA_ROOT="${INTERLINK_DATA_ROOT:-${INTERLINK_DIR}/jobs}"
HPC_TOOLS_DIR="${HPC_TOOLS_DIR:-${HPC_PROJECT_ROOT}/tools}"
HPC_ZOT_DIR="${HPC_PROJECT_ROOT}/zot}"
ZOT_VERSION="${ZOT_VERSION:-v2.1.23}"
LOGIN_RELAY_HOST="${LOGIN_RELAY_HOST:-10.1.0.2}"
OBJECT_STORE_PORT="${OBJECT_STORE_PORT:-19001}"
K8S_API_PORT="${K8S_API_PORT:-19002}"
ZOT_PORT="${ZOT_PORT:-19003}"

echo "[1/6] Preparing InterLink directory"
mkdir -p "$INTERLINK_DIR"
cd "$INTERLINK_DIR"
mkdir -p "$INTERLINK_DATA_ROOT"

echo "[2/6] Downloading InterLink Slurm Sidecar binary"
INTERLINK_RELEASE_BASE="https://github.com/interlink-hq/interlink-slurm-plugin/releases/download/${INTERLINK_SIDECAR_VERSION}"
wget "$INTERLINK_RELEASE_BASE/interlink-sidecar-slurm_Linux_x86_64"
chmod +x interlink-sidecar-slurm_Linux_x86_64
touch "$INTERLINK_DIR/sidecar.log"

echo "[3/6] Writing Slurm sidecar configuration"
cat <<EOF > "$INTERLINK_DIR/SlurmConfig.yaml"
SidecarURL: "http://127.0.0.1"
SidecarPort: "4000"
SbatchPath: "/home/isabelmoutinho/bin/sbatch-subpath-fix"
ScancelPath: "/usr/bin/scancel"
SqueuePath: "/usr/bin/squeue"
SinfoPath: "/usr/bin/sinfo"
ImagePrefix: "docker://${LOGIN_RELAY_HOST}:${ZOT_PORT}/"
SingularityPath: "singularity"
SingularityPrefix: ""
SingularityDefaultOptions:
  - "--no-eval"
  - "-B"
  - "${HPC_TOOLS_DIR}:/tools:ro"
  - "-B"
  - "${HPC_TOOLS_DIR}/hosts:/etc/hosts:ro"
ExportPodData: true
DataRootFolder: "${INTERLINK_DATA_ROOT}/"
Namespace: "vk"
BashPath: /bin/bash
VerboseLogging: true
ErrorsOnlyLogging: false
EnableProbes: true
EOF

chmod +x "$INTERLINK_DIR/SlurmConfig.yaml"

echo "[5/6] Enabling user session and creating systemd user services"
loginctl enable-linger "$HPC_USER" || true

mkdir -p ~/.config/systemd/user

cat <<EOF > ~/.config/systemd/user/interlink-sidecar.service
[Unit]
Description=InterLink Slurm Sidecar
After=network.target

[Service]
Environment=SLURMCONFIGPATH=${INTERLINK_DIR}/SlurmConfig.yaml
Environment=SHARED_FS=true
ExecStart=${INTERLINK_DIR}/interlink-sidecar-slurm_Linux_x86_64
WorkingDirectory=${INTERLINK_DIR}
Restart=always
RestartSec=5
StandardOutput=append:${INTERLINK_DIR}/sidecar.log
StandardError=append:${INTERLINK_DIR}/sidecar.log

[Install]
WantedBy=default.target
EOF

# Enable Service
echo "[6/6] Reloading systemd and enabling user services"
systemctl --user daemon-reload
systemctl --user enable --now interlink-sidecar

#--------------------------------------------

cat <<EOF > "$INTERLINK_DIR/relay.py"
import socket, threading, sys

BIND = "${LOGIN_RELAY_HOST}"
PORTS = [${OBJECT_STORE_PORT}, ${K8S_API_PORT}]

def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try: s.shutdown(socket.SHUT_RDWR)
            except OSError: pass
            s.close()

def handle(client, port):
    try:
        upstream = socket.create_connection(("127.0.0.1", port), timeout=10)
        upstream.settimeout(None)
    except OSError as e:
        print(f"upstream 127.0.0.1:{port} failed: {e}", flush=True)
        client.close()
        return
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()

def serve(port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((BIND, port))
    s.listen(128)
    print(f"relaying {BIND}:{port} -> 127.0.0.1:{port}", flush=True)
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle, args=(c, port), daemon=True).start()

for p in PORTS:
    threading.Thread(target=serve, args=(p,), daemon=True).start()
threading.Event().wait()
EOF

chmod +x "$INTERLINK_DIR/relay.py"

cat <<EOF > ~/.config/systemd/user/interlink-relay.service
[Unit]
Description=Relay ${LOGIN_RELAY_HOST}:${OBJECT_STORE_PORT}/${K8S_API_PORT} to loopback SSH reverse forwards

[Service]
ExecStart=/usr/bin/python3 $INTERLINK_DIR/relay.py
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

# -----------------------------------------------

mkdir -p ~/bin ~/.config/zot "$HPC_ZOT_DIR"
curl -L -o ~/bin/zot \
  https://github.com/project-zot/zot/releases/download/${ZOT_VERSION}/zot-linux-amd64
chmod +x ~/bin/zot

cat > ~/.config/zot/config.json <<EOF
{
  "distSpecVersion": "1.1.1",
  "storage": { "rootDirectory": "$HPC_ZOT_DIR", "gc": true, "dedupe": false },
  "http": { "address": "10.1.0.2", "port": "19003" },
  "log": { "level": "info" },
  "extensions": { "sync": { "registries": [
    { "urls": ["https://registry-1.docker.io"],
      "onDemand": true, "tlsVerify": true,
      "content": [ { "prefix": "**" } ] }
  ] } }
}
EOF

cat > ~/.config/systemd/user/zot.service <<EOF
[Unit]
Description=zot pull-through registry cache
After=network-online.target

[Service]
ExecStart=%h/bin/zot serve %h/.config/zot/config.json
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now interlink-relay
systemctl --user enable --now zot

# Checks

# Connections
# ss -tln | grep 4000

# Logs
# cat /projects/EEHPC-DEV-2026D02-075/.interlink/sidecar.log
# tail -20 /projects/EEHPC-DEV-2026D02-075/.interlink/sidecar.log
# Service Logs Live
# journalctl --user -u interlink-sidecar -f
# Service Logs History
# journalctl --user -u interlink-sidecar

# Service Status
# systemctl --user status interlink-sidecar

# Control

# Service Start
# systemctl --user start interlink-sidecar

# Service Stop
# systemctl --user stop interlink-sidecar

# Service Restart
# systemctl --user restart interlink-sidecar

# Disable Autostart Service
# systemctl --user disable interlink-sidecar

# TEMP FIX
mkdir -p ~/bin
cat > ~/bin/sbatch-subpath-fix <<'EOF'
#!/bin/bash
# subPath fix for the interLink Slurm plugin (tested with 0.6.3), as its SbatchPath.
# Runs on the LOGIN node, called by the plugin as: sbatch <job folder>/job.slurm
#
# The only thing it does: Argo mounts each input artifact into 'main' (and into 'wait', under
# /mainctrfs) from the emptyDir 'input-artifacts' with subPath=<artifact name>. The plugin ignores
# subPath on emptyDirs (pkg/slurm/prepare.go, mountData: --bind <emptyDir>:<mountPath>), so the
# container sees a directory where Argo put a file. This rewrites those binds to
# <emptyDir>/<artifact name>, then submits with the real sbatch, unchanged otherwise.
# To be removed once the plugin honours subPath: upstream.patch in this folder is that fix (9 lines and
# a unit test, against the plugin's 0.6.3), not proposed upstream yet. Argo cannot be configured around
# it: its controller hard-codes this mount. hpc.sh install writes subpath-fix.conf next to the installed
# copy, with the path of the real sbatch.
#
# Nothing may be printed on stderr unless submission failed: the plugin treats any stderr
# output as a failed submission. Diagnostics go to <job folder>/subpath-fix.log.
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL_SBATCH=/usr/bin/sbatch
# shellcheck disable=SC1091
[ -f "$HERE/subpath-fix.conf" ] && source "$HERE/subpath-fix.conf"
SLURM_FILE="$1"
DIR="$(dirname "$SLURM_FILE")"
JOB="$DIR/job.sh"
LOG="$DIR/subpath-fix.log"
log() { echo "$(date -Is) $*" >>"$LOG"; }

# Always hand Slurm a job.sh that is a new file (copy, then rename). The plugin's own job.sh can
# still count as open for writing where the job runs (seen on the testbed, whose compute node is
# also the NFS server), and executing it then fails with "Text file busy".
submit() {
  if [ -f "$JOB" ] && cp -p "$JOB" "$JOB.new" 2>/dev/null; then
    [ -n "${1:-}" ] && printf '%s\n' "$1" >"$JOB.new"
    mv -f "$JOB.new" "$JOB"
  fi
  exec "$REAL_SBATCH" "$SLURM_FILE"
}

# Not every container's env file carries ARGO_TEMPLATE (main's does not): take one that does.
ENVF="$(grep -l '^ARGO_TEMPLATE=' "$DIR"/*_envfile.properties 2>/dev/null | head -n 1)"
if [ ! -f "$JOB" ] || [ -z "$ENVF" ]; then
  submit
fi

# ARGO_TEMPLATE maps each input artifact's path to its name. No JSON parser needed: Argo writes the
# template's fields in a fixed order (name, inputs, outputs, ...) and each artifact as
# {"name":"...","path":"...",...}, so the input artifacts are the name/path pairs before "outputs".
# shellcheck disable=SC1090
TPL="$( set +u; set -a; source "$ENVF" >/dev/null 2>&1; printf '%s' "${ARGO_TEMPLATE:-}" )"
TPL="${TPL%%\"outputs\":*}"
MAP="$(printf '%s' "$TPL" | grep -o '"name":"[^"]*","path":"[^"]*"' | awk -F'"' '{print $8 "\t" $4}')"
[ -n "$MAP" ] || { log "no input artifacts in ARGO_TEMPLATE: nothing to rewrite"; submit; }

NEWJOB="$(cat "$JOB")"
ED="$DIR/emptyDirs/input-artifacts"
changed=0
while IFS=$'\t' read -r apath aname; do
  [ -n "$apath" ] || continue
  # main mounts the artifact at <path>, wait at /mainctrfs<path>
  for dest in "$apath" "/mainctrfs$apath"; do
    from="--bind $ED:$dest:"
    to="--bind $ED/$aname:$dest:"
    if [[ "$NEWJOB" == *"$from"* ]]; then
      NEWJOB="${NEWJOB//"$from"/"$to"}"; changed=1
      log "subPath: $dest <- input-artifacts/$aname"
    fi
  done
done <<<"$MAP"

if [ "$changed" = 1 ]; then
  cp -p "$JOB" "$DIR/job.sh.orig"
  submit "$NEWJOB"
fi
submit
EOF
chmod +x ~/bin/sbatch-subpath-fix

# the script sources this file to find the real sbatch
echo 'REAL_SBATCH=/usr/bin/sbatch' > ~/bin/subpath-fix.conf