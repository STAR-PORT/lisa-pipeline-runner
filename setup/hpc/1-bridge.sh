#!/usr/bin/env bash
set -euo pipefail

# Customizable environment variables:
#   HPC_PROJECT_ROOT          - root path for project files (default: /projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner)
#   HPC_USER                  - user to enable lingering for (default: current user)
#   HPC_WORK                  - local work path for auxiliary tools (default: $HOME/work)
#   HPC_USER_HOME             - home directory of the HPC user (default: $HOME)
#   INTERLINK_SIDECAR_VERSION - InterLink sidecar release version (default: 0.6.1)
#   INTERLINK_DIR             - InterLink install/config directory (default: ${HPC_PROJECT_ROOT}/.interlink)
#   SYNC_SCRIPT_DIR           - path for sync scripts (default: ${HPC_PROJECT_ROOT}/sync)
#   TSOCKS_PATH               - tsocks library path (default: ${HPC_WORK}/tsocks-1.8beta5+ds1/libtsocks.so)
#   TSOCKS_LOGIN_NODE         - login node host name (default: login01)
#   INTERLINK_DATA_ROOT       - job data root inside InterLink (default: ${INTERLINK_DIR}/jobs)

# Load runtime configuration from the wrapper if available.
HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner}"
HPC_USER="${HPC_USER:-${USER:-$(whoami)}}"
HPC_WORK="${HPC_WORK:-${WORK:-$HOME/work}}"
HPC_USER_HOME="${HPC_USER_HOME:-$HOME}"
INTERLINK_SIDECAR_VERSION="${INTERLINK_SIDECAR_VERSION:-0.6.1}"
INTERLINK_DIR="${INTERLINK_DIR:-${HPC_PROJECT_ROOT}/.interlink}"
SYNC_SCRIPT_DIR="${SYNC_SCRIPT_DIR:-${HPC_PROJECT_ROOT}/sync}"
TSOCKS_PATH="${TSOCKS_PATH:-${HPC_WORK}/tsocks-1.8beta5+ds1/libtsocks.so}"
TSOCKS_LOGIN_NODE="${TSOCKS_LOGIN_NODE:-login01}"
INTERLINK_DATA_ROOT="${INTERLINK_DATA_ROOT:-${INTERLINK_DIR}/jobs}"

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
SbatchPath: "/usr/bin/sbatch"
ScancelPath: "/usr/bin/scancel"
SqueuePath: "/usr/bin/squeue"
SinfoPath: "/usr/bin/sinfo"
CommandPrefix: "${SYNC_SCRIPT_DIR}/sync-data.sh"
ImagePrefix: "docker://"
SingularityPath: "singularity"
SingularityPrefix: ""
SingularityDefaultOptions:
  - "-B"
  - "${HPC_PROJECT_ROOT}/data/shared:/shared:ro"
ExportPodData: true
DataRootFolder: "${INTERLINK_DATA_ROOT}/"
Namespace: "vk"
Tsocks: false
TsocksPath: "${TSOCKS_PATH}"
TsocksLoginNode: "${TSOCKS_LOGIN_NODE}"
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
