#!/usr/bin/env bash
set -euo pipefail

# Set WORK if not already set (common in HPC environments)
WORK="${WORK:-$HOME/work}"

# Ensure USER is set (fallback to whoami if unset)
USER="${USER:-$(whoami)}"

echo "[1/6] Preparing InterLink directory"
mkdir -p "/projects/EEHPC-DEV-2026D02-075/.interlink"
cd "/projects/EEHPC-DEV-2026D02-075/.interlink"
mkdir -p "/projects/EEHPC-DEV-2026D02-075/.interlink/jobs"

echo "[2/6] Downloading InterLink Slurm Sidecar binary"
wget https://github.com/interlink-hq/interlink-slurm-plugin/releases/download/0.6.1/interlink-sidecar-slurm_Linux_x86_64
chmod +x interlink-sidecar-slurm_Linux_x86_64
touch /projects/EEHPC-DEV-2026D02-075/.interlink/sidecar.log
cd ..

echo "[3/6] Writing Slurm sidecar configuration"
cat <<EOF > /projects/EEHPC-DEV-2026D02-075/.interlink/SlurmConfig.yaml
SidecarURL: "http://127.0.0.1"
SidecarPort: "4000"
SbatchPath: "/usr/bin/sbatch"
ScancelPath: "/usr/bin/scancel"
SqueuePath: "/usr/bin/squeue"
SinfoPath: "/usr/bin/sinfo"
CommandPrefix: "/projects/EEHPC-DEV-2026D02-075/sync/sync-inputs.sh"
ImagePrefix: "docker://"
SingularityPath: "singularity"
SingularityPrefix: ""
SingularityDefaultOptions:
  - "-B"
  - "/projects/EEHPC-DEV-2026D02-075"
  - "-B"
  - "/home/isabelmoutinho"
ExportPodData: true
DataRootFolder: "/projects/EEHPC-DEV-2026D02-075/.interlink/jobs/"
Namespace: "vk"
Tsocks: false
TsocksPath: "$WORK/tsocks-1.8beta5+ds1/libtsocks.so"
TsocksLoginNode: "login01"
BashPath: /bin/bash
VerboseLogging: true
ErrorsOnlyLogging: false
EnableProbes: true
EOF

chmod +x /projects/EEHPC-DEV-2026D02-075/.interlink/SlurmConfig.yaml

echo "[5/6] Enabling user session and creating systemd user services"
loginctl enable-linger $USER

mkdir -p ~/.config/systemd/user

cat <<EOF > ~/.config/systemd/user/interlink-sidecar.service
[Unit]
Description=InterLink Slurm Sidecar
After=network.target

[Service]
Environment=SLURMCONFIGPATH=/projects/EEHPC-DEV-2026D02-075/.interlink/SlurmConfig.yaml
Environment=SHARED_FS=true
ExecStart=/projects/EEHPC-DEV-2026D02-075/.interlink/interlink-sidecar-slurm_Linux_x86_64
WorkingDirectory=/projects/EEHPC-DEV-2026D02-075/.interlink
Restart=always
RestartSec=5
StandardOutput=append:/projects/EEHPC-DEV-2026D02-075/.interlink/sidecar.log
StandardError=append:/projects/EEHPC-DEV-2026D02-075/.interlink/sidecar.log

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
