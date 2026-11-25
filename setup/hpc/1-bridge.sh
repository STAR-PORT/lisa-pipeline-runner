#!/usr/bin/env bash
set -euo pipefail

# Customizable environment variables:
#   HPC_PROJECT_ROOT          - root path for project files (default: /projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner)
#   HPC_USER                  - user to enable lingering for (default: current user)
#   INTERLINK_SIDECAR_VERSION - InterLink sidecar release version (default: 0.6.1)
#   INTERLINK_DIR             - InterLink install/config directory (default: ${HPC_PROJECT_ROOT}/.interlink)
#   INTERLINK_DATA_ROOT       - job data root inside InterLink (default: ${INTERLINK_DIR}/jobs)
#   HPC_TOOLS_DIR             - shared tools directory mounted into Slurm containers (default: ${HPC_PROJECT_ROOT}/tools)

HPC_PROJECT_ROOT="${HPC_PROJECT_ROOT:-/projects/EEHPC-DEV-2026D02-075/lisa-pipeline-runner}"
HPC_USER="${HPC_USER:-${USER:-$(whoami)}}"
INTERLINK_SIDECAR_VERSION="${INTERLINK_SIDECAR_VERSION:-0.6.1}"
INTERLINK_DIR="${INTERLINK_DIR:-${HPC_PROJECT_ROOT}/.interlink}"
INTERLINK_DATA_ROOT="${INTERLINK_DATA_ROOT:-${INTERLINK_DIR}/jobs}"
HPC_TOOLS_DIR="${HPC_TOOLS_DIR:-${HPC_PROJECT_ROOT}/tools}"

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
ImagePrefix: "docker://"
SingularityPath: "singularity"
SingularityPrefix: ""
SingularityDefaultOptions:
	- "--bind ${HPC_TOOLS_DIR}:/tools:ro"
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
